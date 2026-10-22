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
||| declares for that normaliser, and normal for them (`Reduct`); and every
||| term a term reduces to reduces on to the term's normal form
||| (`reachesNormalForm`). That is the trust Idris's own type checker rests
||| on, which decides conversion by comparing normal forms, and a program
||| that proves its readings of terms sound against `Reduces` needs no
||| check, when it runs, that the evaluator agreed with it. Proved from the
||| definitions: reduction is closed under every map of terms that keeps
||| what a step reads (`mappedReduces`), so under strengthening
||| (`reducesStrengthened`) and under putting values in for fresh names
||| (`substitutes`); values put in for names that stand for a scope's
||| variables are put in for the variables (`substitutesMarkers`), and node
||| by node (`putIn`); and a name made full is the full name of the
||| definition it names (`definedFullName`). Beside them stand facts of the
||| context: that it makes one entry for each full name and records no
||| resolved name as one, so that two resolved names name one entry exactly
||| when their full names agree (`fullNameSameEntry`), and that none of its
||| definitions names one of the frontend's probes (`probesFresh`); and
||| facts of the hosts that run this compiler: that the runtime's equality
||| of integers is reflexive and symmetric, from which Idris's equality of
||| names is proved so; and that what the evaluator's table of primitives
||| computes stays within a bound that grows with its arguments' sizes
||| (`computedWithin`).
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
-- applied only where a statement is a fact no proof here follows: of the
-- evaluator, which runs in `Core`, to what the normalisers give (`reduct`)
-- and to a term's reducts and its normal form (`reachesNormalForm`); of
-- the context, which `Core` actions build, to the full names its entries
-- hold (`oneEntryPerName`, `fullNameUnresolved`) and to the names its
-- definitions hold (`probesFresh`); and of the hosts' runtime, to its
-- comparison of integers (`intEqualityReflexive`, `intEqualitySymmetric`)
-- and to what the table of primitives computes (`computedWithin`).
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
  ||| match, by the evaluator's comparison of constants, nor an alternative
  ||| that binds fields.
  OtherPrimitiveType : (0 _ : (map PrT (isConstantType (dropNS cn)) == Just c) = False) ->
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
  ||| A constant the alternative's is not equal to, by the evaluator's
  ||| comparison of constants: each type's own equality, a double's the
  ||| runtime's, by which no NaN is equal to itself and 0.0 is -0.0.
  OtherConstant : (0 _ : (c == c') = False) -> Misses ctx (PrimVal fc c') (ConstCase c sc)

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
    ToLeaf : Chooses ev ctx env (STerm i rhs) (substs (mkSizeOf args) env (embed {outer = vars} rhs))
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
    ||| A primitive type, matched by its name, by the evaluator's comparison
    ||| of constants.
    ByPrimitiveType : (0 _ : (map PrT (isConstantType (dropNS cn)) == Just c) = True) ->
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
    ||| A constant equal to the alternative's, by the evaluator's comparison
    ||| of constants (`OtherConstant`): not its syntax, since two doubles
    ||| can be equal and differ, and a NaN differs from itself.
    ByConstant : (0 _ : (c == c') = True) -> Chooses ev ctx env sc v ->
                 Matches ev ctx env (PrimVal fc c') (ConstCase c sc) v
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
||| normal form. It is trusted because it holds of the terms and contexts
||| Idris's checker accepts, which no definition here singles out: on a
||| term whose constructor's tag and name disagree, a case can both take
||| and miss an alternative, and two reducts need meet nowhere.
export
0 reachesNormalForm : (r : Reduct form ctx t) -> Reduces (evaluationOf form) ctx t u ->
                      Reduces (evaluationOf form) ctx u r.value
reachesNormalForm _ _ = trusted

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

||| Which names of a set of bounds a term is searched for: those of bound
||| references and of unknowns, both of which `refsToLocals` turns into
||| variables; or those of unknowns alone, which a step of the evaluator
||| reads (`Solve`).
public export
data Naming = BoundOrUnknown | UnknownOnly

-- Whether a bound reference's name counts for a naming.
public export
boundCounts : Naming -> Bounds ns -> Name -> Bool
boundCounts BoundOrUnknown bs n = replaces bs n
boundCounts UnknownOnly bs n = False

mutual
  ||| Whether a term names one of the names a set of bounds replaces, where
  ||| the naming counts it: in a bound reference or an unknown, where
  ||| `refsToLocals` puts a local in for it.
  public export
  mentions : Naming -> Bounds ns -> Term vars -> Bool
  mentions k bs (Local fc l idx p) = False
  mentions k bs (Ref fc Bound n) = boundCounts k bs n
  mentions k bs (Ref fc nt n) = False
  mentions k bs (Meta fc m i args) = replaces bs m || mentionsIn k bs args
  mentions k bs (Bind fc x b sc) = mentionsInBinder k bs b || mentions k bs sc
  mentions k bs (App fc f a) = mentions k bs f || mentions k bs a
  mentions k bs (As fc s n t) = mentions k bs n || mentions k bs t
  mentions k bs (TDelayed fc r t) = mentions k bs t
  mentions k bs (TDelay fc d ty a) = mentions k bs ty || mentions k bs a
  mentions k bs (TForce fc r t) = mentions k bs t
  mentions k bs (PrimVal fc c) = False
  mentions k bs (Erased fc (Dotted t)) = mentions k bs t
  mentions k bs (Erased fc _) = False
  mentions k bs (TType fc u) = False

  public export
  mentionsIn : Naming -> Bounds ns -> List (Term vars) -> Bool
  mentionsIn k bs [] = False
  mentionsIn k bs (t :: ts) = mentions k bs t || mentionsIn k bs ts

  public export
  mentionsInBinder : Naming -> Bounds ns -> Binder (Term vars) -> Bool
  mentionsInBinder k bs (Lam fc c p ty) = mentionsInPi k bs p || mentions k bs ty
  mentionsInBinder k bs (Let fc c val ty) = mentions k bs val || mentions k bs ty
  mentionsInBinder k bs (Pi fc c p ty) = mentionsInPi k bs p || mentions k bs ty
  mentionsInBinder k bs (PVar fc c p ty) = mentionsInPi k bs p || mentions k bs ty
  mentionsInBinder k bs (PLet fc c val ty) = mentions k bs val || mentions k bs ty
  mentionsInBinder k bs (PVTy fc c ty) = mentions k bs ty

  public export
  mentionsInPi : Naming -> Bounds ns -> PiInfo (Term vars) -> Bool
  mentionsInPi k bs (DefImplicit t) = mentions k bs t
  mentionsInPi k bs _ = False

mutual
  ||| Whether a case tree's leaves name one of the names a set of bounds
  ||| replaces, as a bound reference or an unknown.
  public export
  treeMentions : Bounds ns -> CaseTree args -> Bool
  treeMentions bs (Case idx p ty alts) = altsMention bs alts
  treeMentions bs (STerm i rhs) = mentions BoundOrUnknown bs rhs
  treeMentions bs (Unmatched msg) = False
  treeMentions bs Impossible = False

  public export
  altsMention : Bounds ns -> List (CaseAlt args) -> Bool
  altsMention bs [] = False
  altsMention bs (alt :: alts) = altMentions bs alt || altsMention bs alts

  public export
  altMentions : Bounds ns -> CaseAlt args -> Bool
  altMentions bs (ConCase n tag cargs sc) = treeMentions bs sc
  altMentions bs (DelayCase ty arg sc) = treeMentions bs sc
  altMentions bs (ConstCase c sc) = treeMentions bs sc
  altMentions bs (DefaultCase sc) = treeMentions bs sc

||| Names fresh for a frozen context: no leaf of the case tree any of its
||| definitions is read to names one, as a bound reference or an unknown.
public export
0 FreshIn : Frozen -> Bounds ns -> Type
FreshIn ctx bs = {0 n : Name} -> {0 d : GlobalDef} -> {0 info : PMDefInfo} -> {0 args : Scope} ->
                 {0 body : Body args} -> {0 tree : CaseTree args} ->
                 Defines ctx n d -> definition d = PMDef info args body -> TreeOf body tree ->
                 treeMentions bs tree = False

||| A bound reference to each name a set of bounds replaces, the first
||| first: what stands for each variable of a scope, by the name of its
||| place, while a term over the scope is closed.
public export
markersOf : FC -> Bounds ns -> SubstEnv ns vars
markersOf fc None = []
markersOf fc (Add _ old bs) = Ref fc Bound old :: markersOf fc bs

||| The name a set of bounds replaces at a variable of its scope.
public export
0 replacedAt : Bounds ns -> Var ns -> Name
replacedAt (Add _ old _) (MkVar First) = old
replacedAt (Add _ _ rest) (MkVar (Later v)) = replacedAt rest (MkVar v)
replacedAt None (MkVar v) impossible

0 markerName : (bs : Bounds ns) -> (w : Var ns) ->
               Var.index (markersOf {vars} fc bs) w = Ref fc Bound (replacedAt bs w)
markerName (Add _ old rest) (MkVar First) = Refl
markerName (Add _ _ rest) (MkVar (Later v)) = markerName rest (MkVar v)
markerName None (MkVar v) impossible

-- Idris's equality of names compares an identifier's index, a machine
-- name's number, a resolved name's index and the like as the runtime's
-- integers, by `prim__eq_Int`, which a proof cannot evaluate at a
-- variable: that comparison is reflexive and symmetric, which is a fact of
-- each host that runs this compiler. Every instance that lifts it to names
-- is public and structural, so from it equality of names is proved
-- reflexive and symmetric.
0 intEqualityReflexive : (x : Int) -> (x == x) = True
intEqualityReflexive _ = trusted

0 intEqualitySymmetric : (x, y : Int) -> (x == y) = False -> (y == x) = False
intEqualitySymmetric _ _ _ = trusted

0 natEqualityReflexive : (k : Nat) -> (k == k) = True
natEqualityReflexive Z = Refl
natEqualityReflexive (S k) = natEqualityReflexive k

0 natEqualitySymmetric : (j, k : Nat) -> (j == k) = False -> (k == j) = False
natEqualitySymmetric Z Z same = same
natEqualitySymmetric Z (S _) _ = Refl
natEqualitySymmetric (S _) Z _ = Refl
natEqualitySymmetric (S j) (S k) same = natEqualitySymmetric j k same

0 identReflexive : (i : Ident) -> (i == i) = True
identReflexive = identEqualityReflexive intEqualityReflexive

0 identSymmetric : (i, j : Ident) -> (i == j) = False -> (j == i) = False
identSymmetric = identEqualitySymmetric intEqualitySymmetric

0 pairSymmetric : (p, q : (Int, Int)) -> (p == q) = False -> (q == p) = False
pairSymmetric (a, b) (c, d) same
    = bothFalse (a == c) (b == d) (c == a) (d == b) (intEqualitySymmetric a c) (intEqualitySymmetric b d) same

0 userNameReflexive : (u : UserName) -> (u == u) = True
userNameReflexive (Basic i) = identReflexive i
userNameReflexive (Field i) = identReflexive i
userNameReflexive Underscore = Refl

0 userNameSymmetric : (u, v : UserName) -> (u == v) = False -> (v == u) = False
userNameSymmetric (Basic i) (Basic j) same = identSymmetric i j same
userNameSymmetric (Field i) (Field j) same = identSymmetric i j same
userNameSymmetric Underscore Underscore same = same
userNameSymmetric (Basic _) (Field _) _ = Refl
userNameSymmetric (Basic _) Underscore _ = Refl
userNameSymmetric (Field _) (Basic _) _ = Refl
userNameSymmetric (Field _) Underscore _ = Refl
userNameSymmetric Underscore (Basic _) _ = Refl
userNameSymmetric Underscore (Field _) _ = Refl

0 nameEqualityReflexive : (n : Name) -> (n == n) = True
nameEqualityReflexive (NS ns n) = rewrite nameEqualityReflexive n in namespaceEqualityReflexive identReflexive ns
nameEqualityReflexive (UN u) = userNameReflexive u
nameEqualityReflexive (MN i k) = rewrite intEqualityReflexive k in identReflexive i
nameEqualityReflexive (PV n k) = rewrite nameEqualityReflexive n in intEqualityReflexive k
nameEqualityReflexive (DN _ n) = nameEqualityReflexive n
nameEqualityReflexive (Nested (a, b) n)
    = rewrite intEqualityReflexive a in rewrite intEqualityReflexive b in nameEqualityReflexive n
nameEqualityReflexive (CaseBlock n k) = rewrite natEqualityReflexive k in nameEqualityReflexive n
nameEqualityReflexive (WithBlock n k) = rewrite natEqualityReflexive k in nameEqualityReflexive n
nameEqualityReflexive (Resolved k) = intEqualityReflexive k

0 nameEqualitySymmetric : (m, n : Name) -> (m == n) = False -> (n == m) = False
nameEqualitySymmetric (NS ms m) (NS ns n) same
    = bothFalse (m == n) (ms == ns) (n == m) (ns == ms) (nameEqualitySymmetric m n)
                (namespaceEqualitySymmetric identSymmetric ms ns) same
nameEqualitySymmetric (UN u) (UN v) same = userNameSymmetric u v same
nameEqualitySymmetric (MN i j) (MN i' j') same
    = bothFalse (j == j') (i == i') (j' == j) (i' == i) (intEqualitySymmetric j j') (identSymmetric i i') same
nameEqualitySymmetric (PV m j) (PV n k) same
    = bothFalse (m == n) (j == k) (n == m) (k == j) (nameEqualitySymmetric m n) (intEqualitySymmetric j k) same
nameEqualitySymmetric (DN _ m) (DN _ n) same = nameEqualitySymmetric m n same
nameEqualitySymmetric (Nested p m) (Nested q n) same
    = bothFalse (p == q) (m == n) (q == p) (n == m) (pairSymmetric p q) (nameEqualitySymmetric m n) same
nameEqualitySymmetric (CaseBlock m j) (CaseBlock n k) same
    = bothFalse (j == k) (m == n) (k == j) (n == m) (natEqualitySymmetric j k) (nameEqualitySymmetric m n) same
nameEqualitySymmetric (WithBlock m j) (WithBlock n k) same
    = bothFalse (j == k) (m == n) (k == j) (n == m) (natEqualitySymmetric j k) (nameEqualitySymmetric m n) same
nameEqualitySymmetric (Resolved j) (Resolved k) same = intEqualitySymmetric j k same
nameEqualitySymmetric (NS _ _) (UN _) _ = Refl
nameEqualitySymmetric (NS _ _) (MN _ _) _ = Refl
nameEqualitySymmetric (NS _ _) (PV _ _) _ = Refl
nameEqualitySymmetric (NS _ _) (DN _ _) _ = Refl
nameEqualitySymmetric (NS _ _) (Nested _ _) _ = Refl
nameEqualitySymmetric (NS _ _) (CaseBlock _ _) _ = Refl
nameEqualitySymmetric (NS _ _) (WithBlock _ _) _ = Refl
nameEqualitySymmetric (NS _ _) (Resolved _) _ = Refl
nameEqualitySymmetric (UN _) (NS _ _) _ = Refl
nameEqualitySymmetric (UN _) (MN _ _) _ = Refl
nameEqualitySymmetric (UN _) (PV _ _) _ = Refl
nameEqualitySymmetric (UN _) (DN _ _) _ = Refl
nameEqualitySymmetric (UN _) (Nested _ _) _ = Refl
nameEqualitySymmetric (UN _) (CaseBlock _ _) _ = Refl
nameEqualitySymmetric (UN _) (WithBlock _ _) _ = Refl
nameEqualitySymmetric (UN _) (Resolved _) _ = Refl
nameEqualitySymmetric (MN _ _) (NS _ _) _ = Refl
nameEqualitySymmetric (MN _ _) (UN _) _ = Refl
nameEqualitySymmetric (MN _ _) (PV _ _) _ = Refl
nameEqualitySymmetric (MN _ _) (DN _ _) _ = Refl
nameEqualitySymmetric (MN _ _) (Nested _ _) _ = Refl
nameEqualitySymmetric (MN _ _) (CaseBlock _ _) _ = Refl
nameEqualitySymmetric (MN _ _) (WithBlock _ _) _ = Refl
nameEqualitySymmetric (MN _ _) (Resolved _) _ = Refl
nameEqualitySymmetric (PV _ _) (NS _ _) _ = Refl
nameEqualitySymmetric (PV _ _) (UN _) _ = Refl
nameEqualitySymmetric (PV _ _) (MN _ _) _ = Refl
nameEqualitySymmetric (PV _ _) (DN _ _) _ = Refl
nameEqualitySymmetric (PV _ _) (Nested _ _) _ = Refl
nameEqualitySymmetric (PV _ _) (CaseBlock _ _) _ = Refl
nameEqualitySymmetric (PV _ _) (WithBlock _ _) _ = Refl
nameEqualitySymmetric (PV _ _) (Resolved _) _ = Refl
nameEqualitySymmetric (DN _ _) (NS _ _) _ = Refl
nameEqualitySymmetric (DN _ _) (UN _) _ = Refl
nameEqualitySymmetric (DN _ _) (MN _ _) _ = Refl
nameEqualitySymmetric (DN _ _) (PV _ _) _ = Refl
nameEqualitySymmetric (DN _ _) (Nested _ _) _ = Refl
nameEqualitySymmetric (DN _ _) (CaseBlock _ _) _ = Refl
nameEqualitySymmetric (DN _ _) (WithBlock _ _) _ = Refl
nameEqualitySymmetric (DN _ _) (Resolved _) _ = Refl
nameEqualitySymmetric (Nested _ _) (NS _ _) _ = Refl
nameEqualitySymmetric (Nested _ _) (UN _) _ = Refl
nameEqualitySymmetric (Nested _ _) (MN _ _) _ = Refl
nameEqualitySymmetric (Nested _ _) (PV _ _) _ = Refl
nameEqualitySymmetric (Nested _ _) (DN _ _) _ = Refl
nameEqualitySymmetric (Nested _ _) (CaseBlock _ _) _ = Refl
nameEqualitySymmetric (Nested _ _) (WithBlock _ _) _ = Refl
nameEqualitySymmetric (Nested _ _) (Resolved _) _ = Refl
nameEqualitySymmetric (CaseBlock _ _) (NS _ _) _ = Refl
nameEqualitySymmetric (CaseBlock _ _) (UN _) _ = Refl
nameEqualitySymmetric (CaseBlock _ _) (MN _ _) _ = Refl
nameEqualitySymmetric (CaseBlock _ _) (PV _ _) _ = Refl
nameEqualitySymmetric (CaseBlock _ _) (DN _ _) _ = Refl
nameEqualitySymmetric (CaseBlock _ _) (Nested _ _) _ = Refl
nameEqualitySymmetric (CaseBlock _ _) (WithBlock _ _) _ = Refl
nameEqualitySymmetric (CaseBlock _ _) (Resolved _) _ = Refl
nameEqualitySymmetric (WithBlock _ _) (NS _ _) _ = Refl
nameEqualitySymmetric (WithBlock _ _) (UN _) _ = Refl
nameEqualitySymmetric (WithBlock _ _) (MN _ _) _ = Refl
nameEqualitySymmetric (WithBlock _ _) (PV _ _) _ = Refl
nameEqualitySymmetric (WithBlock _ _) (DN _ _) _ = Refl
nameEqualitySymmetric (WithBlock _ _) (Nested _ _) _ = Refl
nameEqualitySymmetric (WithBlock _ _) (CaseBlock _ _) _ = Refl
nameEqualitySymmetric (WithBlock _ _) (Resolved _) _ = Refl
nameEqualitySymmetric (Resolved _) (NS _ _) _ = Refl
nameEqualitySymmetric (Resolved _) (UN _) _ = Refl
nameEqualitySymmetric (Resolved _) (MN _ _) _ = Refl
nameEqualitySymmetric (Resolved _) (PV _ _) _ = Refl
nameEqualitySymmetric (Resolved _) (DN _ _) _ = Refl
nameEqualitySymmetric (Resolved _) (Nested _ _) _ = Refl
nameEqualitySymmetric (Resolved _) (CaseBlock _ _) _ = Refl
nameEqualitySymmetric (Resolved _) (WithBlock _ _) _ = Refl

0 orFalse : (a : Bool) -> (a || b) = False -> (a = False, b = False)
orFalse False prf = (Refl, prf)
orFalse True prf = absurd prf

0 andTrue : (a : Bool) -> (a && b) = True -> (a = True, b = True)
andTrue True prf = (Refl, prf)
andTrue False prf = absurd prf

0 notTrue : (a : Bool) -> not a = True -> a = False
notTrue False _ = Refl
notTrue True prf = absurd prf

-- A name a set of bounds does not replace is at none of them.
0 noneAt : (bs : Bounds ns) -> replaces bs n = False -> NoneAt bs n
noneAt None _ = NoneHere
noneAt (Add _ old rest) none = NotThis (fst (orFalse (n == old) none)) (noneAt rest (snd (orFalse (n == old) none)))

-- A name a set of bounds does not replace is unequal to each it does.
0 replacesAt : (bs : Bounds ns) -> replaces bs n = False -> (w : Var ns) -> (n == replacedAt bs w) = False
replacesAt (Add _ old rest) none (MkVar First) = fst (orFalse (n == old) none)
replacesAt (Add _ old rest) none (MkVar (Later v)) = replacesAt rest (snd (orFalse (n == old) none)) (MkVar v)
replacesAt None _ (MkVar v) impossible

-- Where the names are apart, each is at the first bound that replaces it:
-- equal to its own, and unequal to each before it.
0 firstAt : (bs : Bounds ns) -> namesApart bs = True -> (w : Var ns) -> FirstAt bs w (replacedAt bs w)
firstAt (Add _ old rest) apart (MkVar First) = AtHere (nameEqualityReflexive old)
firstAt (Add _ old rest) apart (MkVar (Later v))
    = AtLater (nameEqualitySymmetric old (replacedAt rest (MkVar v))
                 (replacesAt rest (notTrue (replaces rest old) (fst (andTrue (not (replaces rest old)) apart))) (MkVar v)))
              (firstAt rest (snd (andTrue (not (replaces rest old)) apart)) (MkVar v))
firstAt None _ (MkVar v) impossible

0 weakenMarker : (o : SizeOf outer) -> (bs : Bounds ns) -> (w : Var ns) ->
                 weakenNs o (Var.index (markersOf {vars} fc bs) w) = Ref fc Bound (replacedAt bs w)
weakenMarker o bs w = trans (cong (weakenNs o) (markerName bs w)) weakenRef

mutual
  -- Values put in for no variables leave a term as it is, at any depth.
  0 substNothing : (o : SizeOf outer) -> (sz : SizeOf []) -> (u : Term (outer ++ vars)) -> substTerm {vars} o sz [] u = u
  substNothing o sz (Local fc r i p) = case range (size o) (size sz) i of
    InFirst lt => localAtSame (substBelow o sz [] p lt) IsLocalAt
    InSecond j _ lt => absurd (replace {p = Nat.LT j} (sizesAgree sz zero) lt)
    PastBoth k eq =>
      localAtSame (replace {p = \x => LocalAt fc r x (substTerm {vars} o sz [] (Local fc r i p))}
                           (sym (trans eq (cong (\x => size o + (x + k)) (sizesAgree sz zero))))
                           (substPast o sz [] p k eq))
                  IsLocalAt
  substNothing o sz (Ref fc nt n) = Refl
  substNothing o sz (Meta fc m k args) = cong (Meta fc m k) (substNothingAll o sz args)
  substNothing o sz (Bind fc x b sc) = cong2 (Bind fc x) (substNothingBinder o sz b) (substNothing (suc o) sz sc)
  substNothing o sz (App fc f a) = cong2 (App fc) (substNothing o sz f) (substNothing o sz a)
  substNothing o sz (As fc s n t) = cong2 (As fc s) (substNothing o sz n) (substNothing o sz t)
  substNothing o sz (TDelayed fc r t) = cong (TDelayed fc r) (substNothing o sz t)
  substNothing o sz (TDelay fc d ty a) = cong2 (TDelay fc d) (substNothing o sz ty) (substNothing o sz a)
  substNothing o sz (TForce fc r t) = cong (TForce fc r) (substNothing o sz t)
  substNothing o sz (PrimVal fc c) = Refl
  substNothing o sz (Erased fc Placeholder) = Refl
  substNothing o sz (Erased fc Impossible) = Refl
  substNothing o sz (Erased fc (Dotted t)) = cong (\x => Erased fc (Dotted x)) (substNothing o sz t)
  substNothing o sz (TType fc u) = Refl

  0 substNothingAll : (o : SizeOf outer) -> (sz : SizeOf []) -> (us : List (Term (outer ++ vars))) ->
                      substTerms {vars} o sz [] us = us
  substNothingAll o sz [] = Refl
  substNothingAll o sz (u :: us) = cong2 (::) (substNothing o sz u) (substNothingAll o sz us)

  0 substNothingBinder : (o : SizeOf outer) -> (sz : SizeOf []) -> (b : Binder (Term (outer ++ vars))) ->
                         substBinder {vars} o sz [] b = b
  substNothingBinder o sz (Lam fc c p ty) = cong2 (Lam fc c) (substNothingPi o sz p) (substNothing o sz ty)
  substNothingBinder o sz (Let fc c v ty) = cong2 (Let fc c) (substNothing o sz v) (substNothing o sz ty)
  substNothingBinder o sz (Pi fc c p ty) = cong2 (Pi fc c) (substNothingPi o sz p) (substNothing o sz ty)
  substNothingBinder o sz (PVar fc c p ty) = cong2 (PVar fc c) (substNothingPi o sz p) (substNothing o sz ty)
  substNothingBinder o sz (PLet fc c v ty) = cong2 (PLet fc c) (substNothing o sz v) (substNothing o sz ty)
  substNothingBinder o sz (PVTy fc c ty) = cong (PVTy fc c) (substNothing o sz ty)

  0 substNothingPi : (o : SizeOf outer) -> (sz : SizeOf []) -> (p : PiInfo (Term (outer ++ vars))) ->
                     substPi {vars} o sz [] p = p
  substNothingPi o sz Implicit = Refl
  substNothingPi o sz Explicit = Refl
  substNothingPi o sz AutoImplicit = Refl
  substNothingPi o sz (DefImplicit t) = cong DefImplicit (substNothing o sz t)

mutual
  ||| Embedding a term names what it named.
  export
  0 mentionsEmbed : (k : Naming) -> (bs : Bounds ns) -> (t : Term vs) -> mentions k bs (embed {outer} t) = mentions k bs t
  mentionsEmbed k bs (Local fc r i p) = Refl
  mentionsEmbed k bs (Ref fc nt n) = Refl
  mentionsEmbed k bs (Meta fc m i args) = cong (\x => replaces bs m || x) (mentionsEmbedAll k bs args)
  mentionsEmbed k bs (Bind fc x b sc) = cong2 (\y, z => y || z) (mentionsEmbedBinder k bs b) (mentionsEmbed k bs sc)
  mentionsEmbed k bs (App fc f a) = cong2 (\y, z => y || z) (mentionsEmbed k bs f) (mentionsEmbed k bs a)
  mentionsEmbed k bs (As fc s n t) = cong2 (\y, z => y || z) (mentionsEmbed k bs n) (mentionsEmbed k bs t)
  mentionsEmbed k bs (TDelayed fc r t) = mentionsEmbed k bs t
  mentionsEmbed k bs (TDelay fc d ty a) = cong2 (\y, z => y || z) (mentionsEmbed k bs ty) (mentionsEmbed k bs a)
  mentionsEmbed k bs (TForce fc r t) = mentionsEmbed k bs t
  mentionsEmbed k bs (PrimVal fc c) = Refl
  mentionsEmbed k bs (Erased fc Placeholder) = Refl
  mentionsEmbed k bs (Erased fc Impossible) = Refl
  mentionsEmbed k bs (Erased fc (Dotted t)) = mentionsEmbed k bs t
  mentionsEmbed k bs (TType fc u) = Refl

  0 mentionsEmbedAll : (k : Naming) -> (bs : Bounds ns) -> (ts : List (Term vs)) ->
                       mentionsIn k bs (embedTerms {outer} ts) = mentionsIn k bs ts
  mentionsEmbedAll k bs [] = Refl
  mentionsEmbedAll k bs (t :: ts) = cong2 (\y, z => y || z) (mentionsEmbed k bs t) (mentionsEmbedAll k bs ts)

  0 mentionsEmbedBinder : (k : Naming) -> (bs : Bounds ns) -> (b : Binder (Term vs)) ->
                          mentionsInBinder k bs (embedBinder {outer} b) = mentionsInBinder k bs b
  mentionsEmbedBinder k bs (Lam fc c p ty) = cong2 (\y, z => y || z) (mentionsEmbedPi k bs p) (mentionsEmbed k bs ty)
  mentionsEmbedBinder k bs (Let fc c v ty) = cong2 (\y, z => y || z) (mentionsEmbed k bs v) (mentionsEmbed k bs ty)
  mentionsEmbedBinder k bs (Pi fc c p ty) = cong2 (\y, z => y || z) (mentionsEmbedPi k bs p) (mentionsEmbed k bs ty)
  mentionsEmbedBinder k bs (PVar fc c p ty) = cong2 (\y, z => y || z) (mentionsEmbedPi k bs p) (mentionsEmbed k bs ty)
  mentionsEmbedBinder k bs (PLet fc c v ty) = cong2 (\y, z => y || z) (mentionsEmbed k bs v) (mentionsEmbed k bs ty)
  mentionsEmbedBinder k bs (PVTy fc c ty) = mentionsEmbed k bs ty

  0 mentionsEmbedPi : (k : Naming) -> (bs : Bounds ns) -> (p : PiInfo (Term vs)) ->
                      mentionsInPi k bs (embedPi {outer} p) = mentionsInPi k bs p
  mentionsEmbedPi k bs Implicit = Refl
  mentionsEmbedPi k bs Explicit = Refl
  mentionsEmbedPi k bs AutoImplicit = Refl
  mentionsEmbedPi k bs (DefImplicit t) = mentionsEmbed k bs t

-- A local a substitution left below the binders it is under, turned back
-- by `mkLocals` and substituted again, is the local substituted once.
0 belowBack : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
              (0 p : IsVar nm i (outer ++ (ns ++ vars))) -> Nat.LT i (size o) ->
              {t : Term (outer ++ vars)} -> LocalAt lfc r i t ->
              substTerm o sz vs (mkLocals {vars} o bs t) = substTerm o sz vs (Local lfc r i p)
belowBack o sz bs vs p lt (IsLocalAt {p = q}) =
  cong (substTerm o sz vs) (localAtSame (mkLocalsBelow {vars} o bs q lt) (IsLocalAt {p}))

-- A local among the variables values are put in for, at any location, is
-- the value.
0 middleBack : (o : SizeOf outer) -> (sz : SizeOf ns) -> (vs : SubstEnv ns vars) -> (w : Var ns) ->
               {t : Term (outer ++ (ns ++ vars))} -> LocalAt mfc r (size o + varIdx w) t ->
               substTerm o sz vs t = weakenNs o (Var.index vs w)
middleBack o sz vs w (IsLocalAt {p = q}) = substMiddle o sz vs q w Refl

-- A local a substitution moved down past the variables it put values in
-- for, moved back up by `mkLocals` and substituted again, is the local
-- substituted once.
0 pastBack : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
             (0 p : IsVar nm i (outer ++ (ns ++ vars))) -> (k : Nat) -> i = size o + (size sz + k) ->
             {t : Term (outer ++ vars)} -> LocalAt lfc r (size o + k) t ->
             substTerm o sz vs (mkLocals {vars} o bs t) = substTerm o sz vs (Local lfc r i p)
pastBack o sz bs vs p k eq (IsLocalAt {p = q}) =
  cong (substTerm o sz vs)
       (localAtSame (replace {p = \x => LocalAt lfc r x (mkLocals {vars} o bs (Local lfc r (size o + k) q))}
                             (trans (cong (\x => x + (size o + k)) (sizesAgree (sizeOf bs) sz))
                                    (trans (swapPlus (size o) (size sz) k) (sym eq)))
                             (mkLocalsPast {vars} o bs q (lteAddRight (size o))))
                    (IsLocalAt {p}))

-- A local, closed with a marker in for it where it is one of the scope's
-- variables, turned back and substituted, is the local substituted: by
-- where its index is, below the binders, among the scope's variables, or
-- past them.
0 localPutBack : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                 namesApart bs = True -> (0 p : IsVar nm i (outer ++ (ns ++ vars))) ->
                 substTerm o sz vs (mkLocals {vars} o bs (substTerm o sz (markersOf {vars} fc bs) (Local lfc r i p)))
                   = substTerm o sz vs (Local lfc r i p)
localPutBack o sz bs vs apart p = case range (size o) (size sz) i of
  InFirst lt => belowBack o sz bs vs p lt (substBelow o sz (markersOf fc bs) p lt)
  InSecond j eq lt =>
    let (w ** wj) = varAt sz j lt
        atW = trans eq (cong (size o +) (sym wj)) in
    trans (cong (\t => substTerm o sz vs (mkLocals {vars} o bs t)) (substMiddle o sz (markersOf fc bs) p w atW))
      (trans (cong (\t => substTerm o sz vs (mkLocals {vars} o bs t)) (weakenMarker o bs w))
        (trans (middleBack o sz vs w (mkLocalsMarker {vars} o bs w (firstAt bs apart w)))
               (sym (substMiddle o sz vs p w atW))))
  PastBoth k eq => pastBack o sz bs vs p k eq (substPast o sz (markersOf fc bs) p k eq)

mutual
  -- A term over a scope, with markers in for the scope's variables, the
  -- markers turned back into the variables and values put in for those, is
  -- the term with the values put in, at any depth, where the names are
  -- apart and the term names none of them.
  0 markersPutBack : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                     namesApart bs = True -> (u : Term (outer ++ (ns ++ vars))) ->
                     mentions BoundOrUnknown bs u = False ->
                     substTerm o sz vs (mkLocals {vars} o bs (substTerm o sz (markersOf {vars} fc bs) u)) = substTerm o sz vs u
  markersPutBack o sz bs vs apart (Local lfc r i p) _ = localPutBack o sz bs vs apart p
  markersPutBack o sz bs vs apart (Ref rfc Bound n) none =
    cong (substTerm o sz vs) (mkLocalsUnreplaced {vars} o bs (noneAt bs none))
  markersPutBack o sz bs vs apart (Ref rfc Func n) _ = Refl
  markersPutBack o sz bs vs apart (Ref rfc (DataCon tag arity) n) _ = Refl
  markersPutBack o sz bs vs apart (Ref rfc (TyCon arity) n) _ = Refl
  markersPutBack o sz bs vs apart (Meta mfc m k args) none =
    trans (cong (substTerm o sz vs) (mkLocalsUnknown {vars} o bs (noneAt bs (fst (orFalse (replaces bs m) none)))))
          (cong (Meta mfc m k) (markersPutBackAll o sz bs vs apart args (snd (orFalse (replaces bs m) none))))
  markersPutBack o sz bs vs apart (Bind bfc x b sc) none =
    cong2 (Bind bfc x) (markersPutBackBinder o sz bs vs apart b (fst (orFalse (mentionsInBinder BoundOrUnknown bs b) none)))
                       (markersPutBack (suc o) sz bs vs apart sc (snd (orFalse (mentionsInBinder BoundOrUnknown bs b) none)))
  markersPutBack o sz bs vs apart (App afc f a) none =
    cong2 (App afc) (markersPutBack o sz bs vs apart f (fst (orFalse (mentions BoundOrUnknown bs f) none)))
                    (markersPutBack o sz bs vs apart a (snd (orFalse (mentions BoundOrUnknown bs f) none)))
  markersPutBack o sz bs vs apart (As afc side n t) none =
    cong2 (As afc side) (markersPutBack o sz bs vs apart n (fst (orFalse (mentions BoundOrUnknown bs n) none)))
                        (markersPutBack o sz bs vs apart t (snd (orFalse (mentions BoundOrUnknown bs n) none)))
  markersPutBack o sz bs vs apart (TDelayed dfc r t) none = cong (TDelayed dfc r) (markersPutBack o sz bs vs apart t none)
  markersPutBack o sz bs vs apart (TDelay dfc d ty a) none =
    cong2 (TDelay dfc d) (markersPutBack o sz bs vs apart ty (fst (orFalse (mentions BoundOrUnknown bs ty) none)))
                         (markersPutBack o sz bs vs apart a (snd (orFalse (mentions BoundOrUnknown bs ty) none)))
  markersPutBack o sz bs vs apart (TForce ffc r t) none = cong (TForce ffc r) (markersPutBack o sz bs vs apart t none)
  markersPutBack o sz bs vs apart (PrimVal pfc c) _ = Refl
  markersPutBack o sz bs vs apart (Erased efc Placeholder) _ = Refl
  markersPutBack o sz bs vs apart (Erased efc Impossible) _ = Refl
  markersPutBack o sz bs vs apart (Erased efc (Dotted t)) none =
    cong (\x => Erased efc (Dotted x)) (markersPutBack o sz bs vs apart t none)
  markersPutBack o sz bs vs apart (TType tfc u) _ = Refl

  0 markersPutBackAll : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                        namesApart bs = True -> (us : List (Term (outer ++ (ns ++ vars)))) ->
                        mentionsIn BoundOrUnknown bs us = False ->
                        substTerms o sz vs (mkLocalsTerms {vars} o bs (substTerms o sz (markersOf {vars} fc bs) us))
                          = substTerms o sz vs us
  markersPutBackAll o sz bs vs apart [] _ = Refl
  markersPutBackAll o sz bs vs apart (u :: us) none =
    cong2 (::) (markersPutBack o sz bs vs apart u (fst (orFalse (mentions BoundOrUnknown bs u) none)))
               (markersPutBackAll o sz bs vs apart us (snd (orFalse (mentions BoundOrUnknown bs u) none)))

  0 markersPutBackBinder : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                           namesApart bs = True -> (b : Binder (Term (outer ++ (ns ++ vars)))) ->
                           mentionsInBinder BoundOrUnknown bs b = False ->
                           substBinder o sz vs (mkLocalsBinder {vars} o bs (substBinder o sz (markersOf {vars} fc bs) b))
                             = substBinder o sz vs b
  markersPutBackBinder o sz bs vs apart (Lam lfc c p ty) none =
    cong2 (Lam lfc c) (markersPutBackPi o sz bs vs apart p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
                      (markersPutBack o sz bs vs apart ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  markersPutBackBinder o sz bs vs apart (Let lfc c v ty) none =
    cong2 (Let lfc c) (markersPutBack o sz bs vs apart v (fst (orFalse (mentions BoundOrUnknown bs v) none)))
                      (markersPutBack o sz bs vs apart ty (snd (orFalse (mentions BoundOrUnknown bs v) none)))
  markersPutBackBinder o sz bs vs apart (Pi lfc c p ty) none =
    cong2 (Pi lfc c) (markersPutBackPi o sz bs vs apart p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
                     (markersPutBack o sz bs vs apart ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  markersPutBackBinder o sz bs vs apart (PVar lfc c p ty) none =
    cong2 (PVar lfc c) (markersPutBackPi o sz bs vs apart p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
                       (markersPutBack o sz bs vs apart ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  markersPutBackBinder o sz bs vs apart (PLet lfc c v ty) none =
    cong2 (PLet lfc c) (markersPutBack o sz bs vs apart v (fst (orFalse (mentions BoundOrUnknown bs v) none)))
                       (markersPutBack o sz bs vs apart ty (snd (orFalse (mentions BoundOrUnknown bs v) none)))
  markersPutBackBinder o sz bs vs apart (PVTy lfc c ty) none =
    cong (PVTy lfc c) (markersPutBack o sz bs vs apart ty none)

  0 markersPutBackPi : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                       namesApart bs = True -> (p : PiInfo (Term (outer ++ (ns ++ vars)))) ->
                       mentionsInPi BoundOrUnknown bs p = False ->
                       substPi o sz vs (mkLocalsPi {vars} o bs (substPi o sz (markersOf {vars} fc bs) p)) = substPi o sz vs p
  markersPutBackPi o sz bs vs apart Implicit _ = Refl
  markersPutBackPi o sz bs vs apart Explicit _ = Refl
  markersPutBackPi o sz bs vs apart AutoImplicit _ = Refl
  markersPutBackPi o sz bs vs apart (DefImplicit t) none = cong DefImplicit (markersPutBack o sz bs vs apart t none)

||| Putting values in for names that stand for a scope's variables is
||| putting them in for the variables. A term over the scope, closed with a
||| reference to each name in for its variables (`markersOf`), those
||| references turned back into the variables (`refsToLocals`) and the
||| values put in for them, is the term with the values put in for its
||| variables, where the names are apart (`namesApart`) and the term names
||| none of them (`mentions`): each reference finds its own name first, and
||| every reference and unknown the term held stays as it was.
export
0 substitutesMarkers : {ns : Scope} -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) -> (t : Term ns) ->
                       namesApart bs = True -> mentions BoundOrUnknown bs t = False ->
                       substs (mkSizeOf ns) vs (refsToLocals bs (substs (mkSizeOf ns) (markersOf {vars} fc bs) (embed {outer = vars} t)))
                         = substs (mkSizeOf ns) vs (embed {outer = vars} t)
substitutesMarkers None [] t _ _ = substNothing zero (mkSizeOf []) (substs (mkSizeOf []) [] (embed t))
substitutesMarkers {ns} (Add new old rest) vs t apart none
    = markersPutBack zero (mkSizeOf ns) (Add new old rest) vs apart (embed t)
                     (trans (mentionsEmbed BoundOrUnknown (Add new old rest) t) none)

------------------------------------------------------------------------------
-- Putting values in, node by node
------------------------------------------------------------------------------

||| Values put in for the names a set of bounds replaces, under `outer`
||| binders: each name turned into the variable it stands for (`mkLocals`)
||| and the value put in for that variable (`substTerm`); with no bounds,
||| the second step alone, as `refsToLocals` skips the first. At no binder
||| it is `substs` after `refsToLocals` (`putInAtTop`). At every node but a
||| bound reference and a local it is that node rebuilt from its parts with
||| the values put in, a binder's scope one binder deeper, and an unknown
||| of no replaced name the same unknown over its arguments put in
||| (`mkLocalsUnknown`): `substTerm` and `mkLocals` are public, so each of
||| those is their definitions unfolded. A bound reference is the value
||| for its name's variable (`putInMarker`) or itself (`putInUnreplaced`),
||| and a local is kept (`putInLocal`).
public export
0 putIn : SizeOf outer -> SizeOf ns -> Bounds ns -> SubstEnv ns vars -> Term (outer ++ vars) -> Term (outer ++ vars)
putIn o sz None vs t = substTerm o sz vs t
putIn o sz (Add new old rest) vs t = substTerm o sz vs (mkLocals o (Add new old rest) t)

||| At no binder, putting values in is `substs` after `refsToLocals`.
export
0 putInAtTop : (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) -> (t : Term vars) ->
               substs sz vs (refsToLocals bs t) = putIn SizeOf.zero sz bs vs t
putInAtTop sz None vs t = Refl
putInAtTop sz (Add new old rest) vs t = Refl

||| A bound reference to the name a set of bounds replaces at a variable,
||| where the names are apart, is the value for that variable, weakened
||| under the binders.
export
0 putInMarker : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                namesApart bs = True -> (w : Var ns) ->
                putIn o sz bs vs (Ref fc Bound (replacedAt bs w)) = weakenNs o (Var.index vs w)
putInMarker o sz (Add new old rest) vs apart w
    = middleBack o sz vs w (mkLocalsMarker {vars} o (Add new old rest) w (firstAt (Add new old rest) apart w))
putInMarker o sz None vs apart (MkVar v) impossible

||| A bound reference to a name no bound replaces stays as it was.
export
0 putInUnreplaced : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                    replaces bs n = False -> putIn o sz bs vs (Ref fc Bound n) = Ref fc Bound n
putInUnreplaced o sz None vs _ = Refl
putInUnreplaced o sz (Add new old rest) vs none
    = cong (substTerm o sz vs) (mkLocalsUnreplaced {vars} o (Add new old rest) (noneAt (Add new old rest) none))

0 belowPut : (o : SizeOf outer) -> (sz : SizeOf ns) -> (vs : SubstEnv ns vars) -> Nat.LT i (size o) ->
             {t : Term (outer ++ (ns ++ vars))} -> LocalAt lfc r i t -> LocalAt lfc r i (substTerm o sz vs t)
belowPut o sz vs lt (IsLocalAt {p = q}) = substBelow o sz vs q lt

0 pastPut : (o : SizeOf outer) -> (sz : SizeOf ns) -> (vs : SubstEnv ns vars) -> (k : Nat) ->
            {t : Term (outer ++ (ns ++ vars))} -> LocalAt lfc r (size sz + (size o + k)) t ->
            LocalAt lfc r (size o + k) (substTerm o sz vs t)
pastPut o sz vs k (IsLocalAt {p = q}) = substPast o sz vs q k (swapPlus (size o) (size sz) k)

||| A local of the term values are put into is kept.
export
0 putInLocal : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
               (0 p : IsVar nm i (outer ++ vars)) -> LocalAt lfc r i (putIn o sz bs vs (Local lfc r i p))
putInLocal o sz None [] p = replace {p = LocalAt lfc r i} (sym (substNothing o sz (Local lfc r i p))) IsLocalAt
putInLocal o sz (Add new old rest) vs p = case range (size o) Z i of
  InFirst lt => belowPut o sz vs lt (mkLocalsBelow {vars} o (Add new old rest) p lt)
  InSecond _ _ lt => absurd lt
  PastBoth k eq =>
    replace {p = \x => LocalAt lfc r x (putIn o sz (Add new old rest) vs (Local lfc r i p))} (sym eq)
      (pastPut o sz vs k
         (replace {p = \x => LocalAt lfc r x (mkLocals o (Add new old rest) (Local lfc r i p))}
                  (trans (cong (\x => x + i) (sizesAgree (sizeOf (Add new old rest)) sz)) (cong (size sz +) eq))
                  (mkLocalsPast {vars} o (Add new old rest) p (replace {p = Nat.LTE (size o)} (sym eq) (lteAddRight (size o))))))

------------------------------------------------------------------------------
-- Maps of terms reduction is closed under
------------------------------------------------------------------------------

-- Two maps of terms are read off a reduction: strengthening, which reads a
-- term over its scope without a variable the term does not mention, and
-- putting values in for fresh names. Each rebuilds every node from its
-- parts but a local and a bound reference, and keeps every unknown. No
-- step of the evaluator reads a bound reference, and none reads a local
-- but by its index, so each step of a term is a step of its image, and
-- reduction is closed under both maps. They are one relation (`Mapped`),
-- so the closure is proved once (`mappedReduces`).

||| Index i of a scope, once the variable after its first o is dropped, is
||| index j: past the dropped one, one less; below it, the same. The
||| dropped one itself has no index there.
public export
data Dropped : (o, i, j : Nat) -> Type where
  DropPast : Dropped Z (S i) i
  DropBefore : Dropped (S o) Z Z
  DropUnder : Dropped o i j -> Dropped (S o) (S i) (S j)

||| What a map of terms does to a local: keeps it, or drops the variable at
||| the depth the map is at, reading every variable past it one lower.
public export
data LocalMove = KeepsLocals | DropsOne

||| How a map moves a local, at a depth.
public export
0 MovesLocal : LocalMove -> (depth, i, j : Nat) -> Type
MovesLocal KeepsLocals c i j = (i = j)
MovesLocal DropsOne c i j = Dropped c i j

||| A reference a map keeps as it is: any but a bound one, and a bound one
||| to a name no bound replaces.
public export
0 KeptRef : Bounds ns -> NameType -> Name -> Type
KeptRef bs Bound n = NoneAt bs n
KeptRef bs Func n = ()
KeptRef bs (DataCon tag arity) n = ()
KeptRef bs (TyCon arity) n = ()

||| Index i of a term whose locals below `cut` are bound in it, once every
||| other variable moves `amount` further out: below the cut, i; past it,
||| that much more.
public export
data ShiftedAt : (cut, amount, i, j : Nat) -> Type where
  BelowCut : (0 _ : Nat.LT i cut) -> (0 _ : j = i) -> ShiftedAt cut amount i j
  PastCut : (k : Nat) -> (0 _ : i = cut + k) -> (0 _ : j = cut + (amount + k)) -> ShiftedAt cut amount i j

mutual
  ||| A term with every local past the cut moved further out, the cut one
  ||| deeper under each binder: the term weakened, as a value put in for a
  ||| name under binders is.
  public export
  data Shifted : (cut, amount : Nat) -> Term xs -> Term ys -> Type where
    ShLocal : {0 p : IsVar n i xs} -> {0 q : IsVar m j ys} -> (0 _ : ShiftedAt c d i j) ->
              Shifted c d (Local fc l i p) (Local fc l j q)
    ShRef : Shifted c d (Ref fc nt nm) (Ref fc nt nm)
    ShMeta : AllShifted c d ts us -> Shifted c d (Meta fc nm k ts) (Meta fc nm k us)
    ShBind : BinderShifted c d b b' -> Shifted (S c) d sc sc' ->
             Shifted c d (Bind fc y b sc) (Bind fc y b' sc')
    ShApp : Shifted c d f f' -> Shifted c d a a' -> Shifted c d (App fc f a) (App fc f' a')
    ShAs : Shifted c d a a' -> Shifted c d t t' -> Shifted c d (As fc s a t) (As fc s a' t')
    ShDelayed : Shifted c d t t' -> Shifted c d (TDelayed fc r t) (TDelayed fc r t')
    ShDelay : Shifted c d ty ty' -> Shifted c d a a' ->
              Shifted c d (TDelay fc e ty a) (TDelay fc e ty' a')
    ShForce : Shifted c d t t' -> Shifted c d (TForce fc r t) (TForce fc r t')
    ShPrim : Shifted c d (PrimVal fc k) (PrimVal fc k)
    ShPlaceholder : Shifted c d (Erased fc Placeholder) (Erased fc Placeholder)
    ShImpossible : Shifted c d (Erased fc Impossible) (Erased fc Impossible)
    ShDotted : Shifted c d t t' -> Shifted c d (Erased fc (Dotted t)) (Erased fc (Dotted t'))
    ShType : Shifted c d (TType fc u) (TType fc u)

  public export
  data AllShifted : (cut, amount : Nat) -> List (Term xs) -> List (Term ys) -> Type where
    ShNone : AllShifted c d [] []
    ShEach : Shifted c d t u -> AllShifted c d ts us -> AllShifted c d (t :: ts) (u :: us)

  public export
  data BinderShifted : (cut, amount : Nat) -> Binder (Term xs) -> Binder (Term ys) -> Type where
    ShLam : PiShifted c d p p' -> Shifted c d ty ty' -> BinderShifted c d (Lam fc r p ty) (Lam fc r p' ty')
    ShLet : Shifted c d v v' -> Shifted c d ty ty' -> BinderShifted c d (Let fc r v ty) (Let fc r v' ty')
    ShPi : PiShifted c d p p' -> Shifted c d ty ty' -> BinderShifted c d (Pi fc r p ty) (Pi fc r p' ty')
    ShPVar : PiShifted c d p p' -> Shifted c d ty ty' -> BinderShifted c d (PVar fc r p ty) (PVar fc r p' ty')
    ShPLet : Shifted c d v v' -> Shifted c d ty ty' -> BinderShifted c d (PLet fc r v ty) (PLet fc r v' ty')
    ShPVTy : Shifted c d ty ty' -> BinderShifted c d (PVTy fc r ty) (PVTy fc r ty')

  public export
  data PiShifted : (cut, amount : Nat) -> PiInfo (Term xs) -> PiInfo (Term ys) -> Type where
    ShImplicit : PiShifted c d Implicit Implicit
    ShExplicit : PiShifted c d Explicit Explicit
    ShAutoImplicit : PiShifted c d AutoImplicit AutoImplicit
    ShDefault : Shifted c d t u -> PiShifted c d (DefImplicit t) (DefImplicit u)

mutual
  ||| A term mapped by a map of terms, at a depth: each local moved as the
  ||| map moves it (`MovesLocal`); a bound reference to a name a set of
  ||| bounds replaces, first at a variable, the value for that variable
  ||| moved out past the depth; every other node rebuilt from its parts
  ||| mapped, a binder's scope one deeper. An unknown named by the bounds is
  ||| mapped by nothing: a step reads an unknown, so a term that names one
  ||| so has no image.
  public export
  data Mapped : LocalMove -> Bounds ns -> SubstEnv ns vars -> Nat -> Term xs -> Term ys -> Type where
    MLocal : {0 p : IsVar n i xs} -> {0 q : IsVar m j ys} -> (0 _ : MovesLocal mv c i j) ->
             Mapped mv bs vals c (Local fc l i p) (Local fc l j q)
    MMarker : (0 _ : FirstAt bs w nm) -> Shifted Z c (Var.index vals w) t' ->
              Mapped mv bs vals c (Ref fc Bound nm) t'
    MRef : (0 _ : KeptRef bs nt nm) -> Mapped mv bs vals c (Ref fc nt nm) (Ref fc nt nm)
    MMeta : (0 _ : NoneAt bs nm) -> AllMapped mv bs vals c ts us ->
            Mapped mv bs vals c (Meta fc nm k ts) (Meta fc nm k us)
    MBind : BinderMapped mv bs vals c b b' -> Mapped mv bs vals (S c) sc sc' ->
            Mapped mv bs vals c (Bind fc y b sc) (Bind fc y b' sc')
    MApp : Mapped mv bs vals c f f' -> Mapped mv bs vals c a a' ->
           Mapped mv bs vals c (App fc f a) (App fc f' a')
    MAs : Mapped mv bs vals c a a' -> Mapped mv bs vals c t t' ->
          Mapped mv bs vals c (As fc s a t) (As fc s a' t')
    MDelayed : Mapped mv bs vals c t t' -> Mapped mv bs vals c (TDelayed fc r t) (TDelayed fc r t')
    MDelay : Mapped mv bs vals c ty ty' -> Mapped mv bs vals c a a' ->
             Mapped mv bs vals c (TDelay fc e ty a) (TDelay fc e ty' a')
    MForce : Mapped mv bs vals c t t' -> Mapped mv bs vals c (TForce fc r t) (TForce fc r t')
    MPrim : Mapped mv bs vals c (PrimVal fc k) (PrimVal fc k)
    MPlaceholder : Mapped mv bs vals c (Erased fc Placeholder) (Erased fc Placeholder)
    MImpossible : Mapped mv bs vals c (Erased fc Impossible) (Erased fc Impossible)
    MDotted : Mapped mv bs vals c t t' -> Mapped mv bs vals c (Erased fc (Dotted t)) (Erased fc (Dotted t'))
    MType : Mapped mv bs vals c (TType fc u) (TType fc u)

  public export
  data AllMapped : LocalMove -> Bounds ns -> SubstEnv ns vars -> Nat -> List (Term xs) -> List (Term ys) -> Type where
    MNone : AllMapped mv bs vals c [] []
    MEach : Mapped mv bs vals c t u -> AllMapped mv bs vals c ts us ->
            AllMapped mv bs vals c (t :: ts) (u :: us)

  public export
  data BinderMapped : LocalMove -> Bounds ns -> SubstEnv ns vars -> Nat -> Binder (Term xs) -> Binder (Term ys) -> Type where
    MLam : PiMapped mv bs vals c p p' -> Mapped mv bs vals c ty ty' ->
           BinderMapped mv bs vals c (Lam fc r p ty) (Lam fc r p' ty')
    MLet : Mapped mv bs vals c v v' -> Mapped mv bs vals c ty ty' ->
           BinderMapped mv bs vals c (Let fc r v ty) (Let fc r v' ty')
    MPi : PiMapped mv bs vals c p p' -> Mapped mv bs vals c ty ty' ->
          BinderMapped mv bs vals c (Pi fc r p ty) (Pi fc r p' ty')
    MPVar : PiMapped mv bs vals c p p' -> Mapped mv bs vals c ty ty' ->
            BinderMapped mv bs vals c (PVar fc r p ty) (PVar fc r p' ty')
    MPLet : Mapped mv bs vals c v v' -> Mapped mv bs vals c ty ty' ->
            BinderMapped mv bs vals c (PLet fc r v ty) (PLet fc r v' ty')
    MPVTy : Mapped mv bs vals c ty ty' -> BinderMapped mv bs vals c (PVTy fc r ty) (PVTy fc r ty')

  public export
  data PiMapped : LocalMove -> Bounds ns -> SubstEnv ns vars -> Nat -> PiInfo (Term xs) -> PiInfo (Term ys) -> Type where
    MImplicit : PiMapped mv bs vals c Implicit Implicit
    MExplicit : PiMapped mv bs vals c Explicit Explicit
    MAutoImplicit : PiMapped mv bs vals c AutoImplicit AutoImplicit
    MDefault : Mapped mv bs vals c t u -> PiMapped mv bs vals c (DefImplicit t) (DefImplicit u)

||| Values put in for a scope's variables, each mapped.
public export
data EnvMapped : LocalMove -> Bounds ns -> SubstEnv ns vars -> Nat -> SubstEnv ds xs -> SubstEnv ds ys -> Type where
  EnvNone : EnvMapped mv bs vals c [] []
  EnvEach : Mapped mv bs vals c t t' -> EnvMapped mv bs vals c env env' ->
            EnvMapped mv bs vals c (t :: env) (t' :: env')

||| A term read over its scope without the variable at index o, which it
||| does not mention: the same term, each index past that variable one
||| lower, under each binder o one deeper. It puts nothing in for a name.
public export
0 Strengthened : Nat -> Term xs -> Term ys -> Type
Strengthened o t t' = Mapped DropsOne None (the (SubstEnv [] []) []) o t t'

||| No bounds keep every reference, so a reader that strengthens a
||| reference keeps it whatever its kind.
export
0 keptByNone : (nt : NameType) -> KeptRef None nt n
keptByNone Bound = NoneHere
keptByNone Func = ()
keptByNone (DataCon tag arity) = ()
keptByNone (TyCon arity) = ()

||| No bounds replace a name, so a strengthened term has no marker.
export
0 noneReplaces : FirstAt None w n -> Void
noneReplaces (AtHere _) impossible
noneReplaces (AtLater _ _) impossible

------------------------------------------------------------------------------
-- Indices
------------------------------------------------------------------------------

0 droppedBelow : {i : Nat} -> Nat.LT i o -> Dropped o i i
droppedBelow {i = Z} (LTESucc _) = DropBefore
droppedBelow {i = S k} (LTESucc lt) = DropUnder (droppedBelow lt)

0 droppedUnder : (a : Nat) -> Dropped c k k' -> Dropped (a + c) (a + k) (a + k')
droppedUnder Z d = d
droppedUnder (S a) d = DropUnder (droppedUnder a d)

-- An index past the first `a` keeps them when it is dropped past them.
0 droppedPeel : (a, c, k : Nat) -> Dropped (a + c) (a + k) j -> (k' : Nat ** (j = a + k', Dropped c k k'))
droppedPeel {j} Z c k d = (j ** (Refl, d))
droppedPeel (S a) c k (DropUnder d) = case droppedPeel a c k d of
  (k' ** (same, d')) => (k' ** (cong S same, d'))

-- An index below the dropped one is kept.
0 droppedBelowCut : (a, x : Nat) -> Nat.LT i a -> Dropped (a + x) i j -> j = i
droppedBelowCut (S a) x (LTESucc _) DropBefore = Refl
droppedBelowCut (S a) x (LTESucc lt) (DropUnder d) = cong S (droppedBelowCut a x lt d)

0 droppedOnce : Dropped o i j -> Dropped o i j' -> j = j'
droppedOnce DropPast DropPast = Refl
droppedOnce DropBefore DropBefore = Refl
droppedOnce (DropUnder d) (DropUnder d') = cong S (droppedOnce d d')

0 droppedAt : i' = i -> j' = j -> Dropped c i j -> Dropped c i' j'
droppedAt Refl Refl d = d

0 pastBy : Nat.LTE a i -> (k : Nat ** i = a + k)
pastBy {i} LTEZero = (i ** Refl)
pastBy (LTESucc lte) = case pastBy lte of
  (k ** same) => (k ** cong S same)

0 movesBelow : (mv : LocalMove) -> Nat.LT i c -> MovesLocal mv c i i
movesBelow KeepsLocals _ = Refl
movesBelow DropsOne lt = droppedBelow lt

0 movesOnce : (mv : LocalMove) -> MovesLocal mv c i j -> MovesLocal mv c i j' -> j = j'
movesOnce KeepsLocals Refl Refl = Refl
movesOnce DropsOne d d' = droppedOnce d d'

-- An index a weakening keeps or moves, the same way for both of two
-- indices that are one.
0 insertKeeps : (a, b : Nat) -> Either (Nat.LT i a, i' = i) (Nat.LTE a i, i' = b + i) ->
                Either (Nat.LT i a, j' = i) (Nat.LTE a i, j' = b + i) -> i' = j'
insertKeeps a b (Left (_, ip)) (Left (_, iq)) = trans ip (sym iq)
insertKeeps a b (Right (_, ip)) (Right (_, iq)) = trans ip (sym iq)
insertKeeps a b (Left (lt, _)) (Right (lte, _)) = void (LTEImpliesNotGT lte lt)
insertKeeps a b (Right (lte, _)) (Left (lt, _)) = void (LTEImpliesNotGT lte lt)

-- A dropped index past `a` variables, `b` more inserted after them: below
-- them it keeps its place, past them it moves past the `b` too, and so
-- does the index it is dropped to.
0 insertDrops : (a, b, c : Nat) -> Dropped (a + c) i j ->
                Either (Nat.LT i a, i' = i) (Nat.LTE a i, i' = b + i) ->
                Either (Nat.LT j a, j' = j) (Nat.LTE a j, j' = b + j) ->
                Dropped (a + (b + c)) i' j'
insertDrops a b c d (Left (lt, ip)) ej = case droppedBelowCut a c lt d of
  Refl => case ej of
    Left (_, iq) => droppedAt ip iq (droppedBelow (transitive lt (lteAddRight {m = b + c} a)))
    Right (lte, _) => void (LTEImpliesNotGT lte lt)
insertDrops a b c d (Right (lte, ip)) ej = case pastBy lte of
  (k ** Refl) => case droppedPeel a c k d of
    (k' ** (Refl, d')) => case ej of
      Left (lt, _) => void (notBelowPlus lt)
      Right (_, iq) =>
        droppedAt (trans ip (swapPlus a b k)) (trans iq (swapPlus a b k')) (droppedUnder a (droppedUnder b d'))

-- The sums a shift past a cut adds up to.
0 insertedPast : (c, e, m, k, z : Nat) -> z + (c + ((e + m) + k)) = c + ((e + (z + m)) + k)
insertedPast c e m k z
    = trans (swapPlus c z ((e + m) + k))
            (cong (c +) (trans (plusAssociative z (e + m) k) (cong (\x => x + k) (swapPlus e z m))))

0 cutBelowPast : (c, e, m, k : Nat) -> Nat.LTE (c + e) (c + ((e + m) + k))
cutBelowPast c e m k = plusLteMonotoneLeft c e ((e + m) + k) (transitive (lteAddRight {m} e) (lteAddRight {m = k} (e + m)))

0 substitutedPast : (c, e, m, k, z : Nat) -> so = c + e -> j = c + ((e + (z + m)) + k) -> j = so + (z + (m + k))
substitutedPast c e m k z eq same
    = trans same
        (trans (trans (cong (c +) (trans (sym (plusAssociative e (z + m) k)) (cong (e +) (sym (plusAssociative z m k)))))
                      (plusAssociative c e (z + (m + k))))
               (cong (\x => x + (z + (m + k))) (sym eq)))

0 keptPast : (c, e, m, k : Nat) -> so = c + e -> so + (m + k) = c + ((e + m) + k)
keptPast c e m k eq
    = trans (cong (\x => x + (m + k)) eq) (trans (sym (plusAssociative c e (m + k))) (cong (c +) (plusAssociative e m k)))

0 shiftedAtOnce : ShiftedAt c d i j -> ShiftedAt c d i j' -> j = j'
shiftedAtOnce (BelowCut _ same) (BelowCut _ same') = trans same (sym same')
shiftedAtOnce {c} {d} (PastCut k past same) (PastCut k' past' same')
    = trans same (trans (cong (\x => c + (d + x)) (plusLeftCancel c k k' (trans (sym past) past'))) (sym same'))
shiftedAtOnce {c} (BelowCut lt _) (PastCut k past _) = void (notBelowPlus (replace {p = \x => Nat.LT x c} past lt))
shiftedAtOnce {c} (PastCut k past _) (BelowCut lt _) = void (notBelowPlus (replace {p = \x => Nat.LT x c} past lt))

------------------------------------------------------------------------------
-- Locals
------------------------------------------------------------------------------

0 mappedLocals : (mv : LocalMove) -> (c : Nat) -> LocalAt fc l i u -> LocalAt fc l j u' ->
                 (0 _ : MovesLocal mv c i j) -> Mapped mv bs vals c u u'
mappedLocals mv c IsLocalAt IsLocalAt moved = MLocal moved

0 shiftedLocals : LocalAt fc l i u -> LocalAt fc l j u' -> (0 _ : ShiftedAt c d i j) -> Shifted c d u u'
shiftedLocals IsLocalAt IsLocalAt at = ShLocal at

0 localsAt : {0 q : IsVar n j ys} -> {0 q' : IsVar n' j' ys} -> j = j' -> Local {vars = ys} fc l j q = Local fc l j' q'
localsAt Refl = localAtSame IsLocalAt IsLocalAt

------------------------------------------------------------------------------
-- No step
------------------------------------------------------------------------------

mutual
  ||| Every term reduces to itself, under every evaluation: each node
  ||| rebuilt from its parts by the congruence that steps under it, each
  ||| part reduced to itself.
  export
  0 reducesToItself : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (t : Term vs) -> Reduces ev ctx t t
  reducesToItself (Local fc l idx p) = ALocal
  reducesToItself (Ref fc nt n) = ARef
  reducesToItself (Meta fc m i args) = AMeta (allReduceToThemselves args)
  reducesToItself (Bind fc x b sc) = ABind (binderReducesToItself b) (reducesToItself sc)
  reducesToItself (App fc f a) = AnApp (reducesToItself f) (reducesToItself a)
  reducesToItself (As fc s n t) = AnAs (reducesToItself n) (reducesToItself t)
  reducesToItself (TDelayed fc r t) = ADelayed (reducesToItself t)
  reducesToItself (TDelay fc r ty a) = ADelay (reducesToItself ty) (reducesToItself a)
  reducesToItself (TForce fc r t) = AForce (reducesToItself t)
  reducesToItself (PrimVal fc c) = APrimVal
  reducesToItself (Erased fc Placeholder) = AnErased APlaceholder
  reducesToItself (Erased fc Impossible) = AnErased AnImpossible
  reducesToItself (Erased fc (Dotted t)) = AnErased (ADotted (reducesToItself t))
  reducesToItself (TType fc u) = AType

  0 allReduceToThemselves : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (ts : List (Term vs)) -> AllReduce ev ctx ts ts
  allReduceToThemselves [] = NoneLeft
  allReduceToThemselves (t :: ts) = Each (reducesToItself t) (allReduceToThemselves ts)

  0 binderReducesToItself : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (b : Binder (Term vs)) -> BinderReduces ev ctx b b
  binderReducesToItself (Lam fc c p ty) = ALam (piReducesToItself p) (reducesToItself ty)
  binderReducesToItself (Let fc c v ty) = ALet (reducesToItself v) (reducesToItself ty)
  binderReducesToItself (Pi fc c p ty) = APi (piReducesToItself p) (reducesToItself ty)
  binderReducesToItself (PVar fc c p ty) = APVar (piReducesToItself p) (reducesToItself ty)
  binderReducesToItself (PLet fc c v ty) = APLet (reducesToItself v) (reducesToItself ty)
  binderReducesToItself (PVTy fc c ty) = APVTy (reducesToItself ty)

  0 piReducesToItself : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (p : PiInfo (Term vs)) -> PiReduces ev ctx p p
  piReducesToItself Implicit = AnImplicit
  piReducesToItself Explicit = AnExplicit
  piReducesToItself AutoImplicit = AnAutoImplicit
  piReducesToItself (DefImplicit t) = ADefImplicit (reducesToItself t)

------------------------------------------------------------------------------
-- Weakening, and values put in, past a cut
------------------------------------------------------------------------------

mutual
  -- Weakening moves every free variable of a term out past the variables it
  -- inserts.
  0 insertShifted : (o : SizeOf local) -> (s : SizeOf new) -> (v : Term (local ++ outer)) ->
                    Shifted (size o) (size s) v (insertNames {outer} o s v)
  insertShifted {outer} o s (Local fc l i p) = case insertNVarNamesIdx {outer} o s (MkNVar p) of
    Left (lt, same) =>
      shiftedLocals IsLocalAt (localAtIdx (insertNVarNames {outer} o s (MkNVar p))) (BelowCut lt same)
    Right (lte, same) => case pastBy lte of
      (k ** past) =>
        shiftedLocals IsLocalAt (localAtIdx (insertNVarNames {outer} o s (MkNVar p)))
          (PastCut k past (trans same (trans (cong (size s +) past) (swapPlus (size o) (size s) k))))
  insertShifted o s (Ref fc nt n) = ShRef
  insertShifted o s (Meta fc n k args) = ShMeta (insertShiftedAll o s args)
  insertShifted o@(MkSizeOf _ _) s (Bind fc x b sc) = ShBind (insertShiftedBinder o s b) (insertShifted (suc o) s sc)
  insertShifted o s (App fc f a) = ShApp (insertShifted o s f) (insertShifted o s a)
  insertShifted o s (As fc side n t) = ShAs (insertShifted o s n) (insertShifted o s t)
  insertShifted o s (TDelayed fc r t) = ShDelayed (insertShifted o s t)
  insertShifted o s (TDelay fc r ty a) = ShDelay (insertShifted o s ty) (insertShifted o s a)
  insertShifted o s (TForce fc r t) = ShForce (insertShifted o s t)
  insertShifted o s (PrimVal fc c) = ShPrim
  insertShifted o s (Erased fc Placeholder) = ShPlaceholder
  insertShifted o s (Erased fc Impossible) = ShImpossible
  insertShifted o s (Erased fc (Dotted t)) = ShDotted (insertShifted o s t)
  insertShifted o s (TType fc u) = ShType

  0 insertShiftedAll : (o : SizeOf local) -> (s : SizeOf new) -> (ts : List (Term (local ++ outer))) ->
                       AllShifted (size o) (size s) ts (insertNamesTerms {outer} o s ts)
  insertShiftedAll o s [] = ShNone
  insertShiftedAll o s (t :: ts) = ShEach (insertShifted o s t) (insertShiftedAll o s ts)

  0 insertShiftedBinder : (o : SizeOf local) -> (s : SizeOf new) -> (b : Binder (Term (local ++ outer))) ->
                          BinderShifted (size o) (size s) b (insertNamesBinder {outer} o s b)
  insertShiftedBinder o s (Lam fc c p ty) = ShLam (insertShiftedPi o s p) (insertShifted o s ty)
  insertShiftedBinder o s (Let fc c v ty) = ShLet (insertShifted o s v) (insertShifted o s ty)
  insertShiftedBinder o s (Pi fc c p ty) = ShPi (insertShiftedPi o s p) (insertShifted o s ty)
  insertShiftedBinder o s (PVar fc c p ty) = ShPVar (insertShiftedPi o s p) (insertShifted o s ty)
  insertShiftedBinder o s (PLet fc c v ty) = ShPLet (insertShifted o s v) (insertShifted o s ty)
  insertShiftedBinder o s (PVTy fc c ty) = ShPVTy (insertShifted o s ty)

  0 insertShiftedPi : (o : SizeOf local) -> (s : SizeOf new) -> (p : PiInfo (Term (local ++ outer))) ->
                      PiShifted (size o) (size s) p (insertNamesPi {outer} o s p)
  insertShiftedPi o s Implicit = ShImplicit
  insertShiftedPi o s Explicit = ShExplicit
  insertShiftedPi o s AutoImplicit = ShAutoImplicit
  insertShiftedPi o s (DefImplicit t) = ShDefault (insertShifted o s t)

-- A value weakened past variables is the value with every free variable
-- moved out past them.
0 shiftedWeaken : (s : SizeOf new) -> (v : Term vars) -> Shifted Z (size s) v (weakenNs s v)
shiftedWeaken s v = insertShifted zero s v

mutual
  -- A value moved out past a cut, then weakened at a depth past the cut, is
  -- moved out past the inserted variables too.
  0 shiftedInsert : (c, e, m : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                    {0 v : Term vs} -> {0 w : Term (local ++ outer)} -> size o = c + e ->
                    Shifted c (e + m) v w -> Shifted c (e + (size s + m)) v (insertNames {outer} o s w)
  shiftedInsert c e m {outer} o s eq (ShLocal {j} {q} (BelowCut lt same)) =
    case insertNVarNamesIdx {outer} o s (MkNVar q) of
      Left (_, ix) =>
        shiftedLocals IsLocalAt (localAtIdx (insertNVarNames {outer} o s (MkNVar q))) (BelowCut lt (trans ix same))
      Right (lte, _) =>
        void (LTEImpliesNotGT (replace {p = \x => Nat.LTE x j} eq lte)
                              (transitive (replace {p = \x => Nat.LT x c} (sym same) lt) (lteAddRight {m = e} c)))
  shiftedInsert c e m {outer} o s eq (ShLocal {j} {q} (PastCut k past same)) =
    case insertNVarNamesIdx {outer} o s (MkNVar q) of
      Left (lt, _) =>
        void (LTEImpliesNotGT (replace {p = \x => Nat.LTE x j} (sym eq)
                                 (replace {p = \y => Nat.LTE (c + e) y} (sym same) (cutBelowPast c e m k)))
                              lt)
      Right (_, ix) =>
        shiftedLocals IsLocalAt (localAtIdx (insertNVarNames {outer} o s (MkNVar q)))
          (PastCut k past (trans ix (trans (cong (size s +) same) (insertedPast c e m k (size s)))))
  shiftedInsert c e m o s eq ShRef = ShRef
  shiftedInsert c e m o s eq (ShMeta ts) = ShMeta (shiftedInsertAll c e m o s eq ts)
  shiftedInsert c e m o@(MkSizeOf _ _) s eq (ShBind b sc) =
    ShBind (shiftedInsertBinder c e m o s eq b) (shiftedInsert (S c) e m (suc o) s (cong S eq) sc)
  shiftedInsert c e m o s eq (ShApp f a) = ShApp (shiftedInsert c e m o s eq f) (shiftedInsert c e m o s eq a)
  shiftedInsert c e m o s eq (ShAs n t) = ShAs (shiftedInsert c e m o s eq n) (shiftedInsert c e m o s eq t)
  shiftedInsert c e m o s eq (ShDelayed t) = ShDelayed (shiftedInsert c e m o s eq t)
  shiftedInsert c e m o s eq (ShDelay ty a) = ShDelay (shiftedInsert c e m o s eq ty) (shiftedInsert c e m o s eq a)
  shiftedInsert c e m o s eq (ShForce t) = ShForce (shiftedInsert c e m o s eq t)
  shiftedInsert c e m o s eq ShPrim = ShPrim
  shiftedInsert c e m o s eq ShPlaceholder = ShPlaceholder
  shiftedInsert c e m o s eq ShImpossible = ShImpossible
  shiftedInsert c e m o s eq (ShDotted t) = ShDotted (shiftedInsert c e m o s eq t)
  shiftedInsert c e m o s eq ShType = ShType

  0 shiftedInsertAll : (c, e, m : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                       {0 vs' : List (Term vs)} -> {0 ws : List (Term (local ++ outer))} -> size o = c + e ->
                       AllShifted c (e + m) vs' ws -> AllShifted c (e + (size s + m)) vs' (insertNamesTerms {outer} o s ws)
  shiftedInsertAll c e m o s eq ShNone = ShNone
  shiftedInsertAll c e m o s eq (ShEach t ts) = ShEach (shiftedInsert c e m o s eq t) (shiftedInsertAll c e m o s eq ts)

  0 shiftedInsertBinder : (c, e, m : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                          {0 b : Binder (Term vs)} -> {0 b' : Binder (Term (local ++ outer))} -> size o = c + e ->
                          BinderShifted c (e + m) b b' -> BinderShifted c (e + (size s + m)) b (insertNamesBinder {outer} o s b')
  shiftedInsertBinder c e m o s eq (ShLam p ty) = ShLam (shiftedInsertPi c e m o s eq p) (shiftedInsert c e m o s eq ty)
  shiftedInsertBinder c e m o s eq (ShLet v ty) = ShLet (shiftedInsert c e m o s eq v) (shiftedInsert c e m o s eq ty)
  shiftedInsertBinder c e m o s eq (ShPi p ty) = ShPi (shiftedInsertPi c e m o s eq p) (shiftedInsert c e m o s eq ty)
  shiftedInsertBinder c e m o s eq (ShPVar p ty) = ShPVar (shiftedInsertPi c e m o s eq p) (shiftedInsert c e m o s eq ty)
  shiftedInsertBinder c e m o s eq (ShPLet v ty) = ShPLet (shiftedInsert c e m o s eq v) (shiftedInsert c e m o s eq ty)
  shiftedInsertBinder c e m o s eq (ShPVTy ty) = ShPVTy (shiftedInsert c e m o s eq ty)

  0 shiftedInsertPi : (c, e, m : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                      {0 p : PiInfo (Term vs)} -> {0 p' : PiInfo (Term (local ++ outer))} -> size o = c + e ->
                      PiShifted c (e + m) p p' -> PiShifted c (e + (size s + m)) p (insertNamesPi {outer} o s p')
  shiftedInsertPi c e m o s eq ShImplicit = ShImplicit
  shiftedInsertPi c e m o s eq ShExplicit = ShExplicit
  shiftedInsertPi c e m o s eq ShAutoImplicit = ShAutoImplicit
  shiftedInsertPi c e m o s eq (ShDefault t) = ShDefault (shiftedInsert c e m o s eq t)

mutual
  -- A value moved out past a cut, then given values for variables at a
  -- depth past the cut, is moved out as many fewer.
  0 shiftedSubst : (c, e, m : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> (env : SubstEnv ds ws) ->
                   {0 v : Term vs} -> {0 w : Term (outer ++ (ds ++ ws))} -> size o = c + e ->
                   Shifted c (e + (size s + m)) v w -> Shifted c (e + m) v (substTerm o s env w)
  shiftedSubst c e m o s env eq (ShLocal {j} {q} (BelowCut lt same)) =
    shiftedLocals IsLocalAt
      (substBelow o s env q (replace {p = Nat.LT j} (sym eq)
                                (transitive (replace {p = \x => Nat.LT x c} (sym same) lt) (lteAddRight {m = e} c))))
      (BelowCut lt same)
  shiftedSubst c e m o s env eq (ShLocal {j} {q} (PastCut k past same)) =
    shiftedLocals IsLocalAt (substPast o s env q (m + k) (substitutedPast c e m k (size s) eq same))
                  (PastCut k past (keptPast c e m k eq))
  shiftedSubst c e m o s env eq ShRef = ShRef
  shiftedSubst c e m o s env eq (ShMeta ts) = ShMeta (shiftedSubstAll c e m o s env eq ts)
  shiftedSubst c e m o@(MkSizeOf _ _) s env eq (ShBind b sc) =
    ShBind (shiftedSubstBinder c e m o s env eq b) (shiftedSubst (S c) e m (suc o) s env (cong S eq) sc)
  shiftedSubst c e m o s env eq (ShApp f a) = ShApp (shiftedSubst c e m o s env eq f) (shiftedSubst c e m o s env eq a)
  shiftedSubst c e m o s env eq (ShAs n t) = ShAs (shiftedSubst c e m o s env eq n) (shiftedSubst c e m o s env eq t)
  shiftedSubst c e m o s env eq (ShDelayed t) = ShDelayed (shiftedSubst c e m o s env eq t)
  shiftedSubst c e m o s env eq (ShDelay ty a) = ShDelay (shiftedSubst c e m o s env eq ty) (shiftedSubst c e m o s env eq a)
  shiftedSubst c e m o s env eq (ShForce t) = ShForce (shiftedSubst c e m o s env eq t)
  shiftedSubst c e m o s env eq ShPrim = ShPrim
  shiftedSubst c e m o s env eq ShPlaceholder = ShPlaceholder
  shiftedSubst c e m o s env eq ShImpossible = ShImpossible
  shiftedSubst c e m o s env eq (ShDotted t) = ShDotted (shiftedSubst c e m o s env eq t)
  shiftedSubst c e m o s env eq ShType = ShType

  0 shiftedSubstAll : (c, e, m : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> (env : SubstEnv ds ws) ->
                      {0 vs' : List (Term vs)} -> {0 us : List (Term (outer ++ (ds ++ ws)))} -> size o = c + e ->
                      AllShifted c (e + (size s + m)) vs' us -> AllShifted c (e + m) vs' (substTerms o s env us)
  shiftedSubstAll c e m o s env eq ShNone = ShNone
  shiftedSubstAll c e m o s env eq (ShEach t ts) = ShEach (shiftedSubst c e m o s env eq t) (shiftedSubstAll c e m o s env eq ts)

  0 shiftedSubstBinder : (c, e, m : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> (env : SubstEnv ds ws) ->
                         {0 b : Binder (Term vs)} -> {0 b' : Binder (Term (outer ++ (ds ++ ws)))} -> size o = c + e ->
                         BinderShifted c (e + (size s + m)) b b' -> BinderShifted c (e + m) b (substBinder o s env b')
  shiftedSubstBinder c e m o s env eq (ShLam p ty) = ShLam (shiftedSubstPi c e m o s env eq p) (shiftedSubst c e m o s env eq ty)
  shiftedSubstBinder c e m o s env eq (ShLet v ty) = ShLet (shiftedSubst c e m o s env eq v) (shiftedSubst c e m o s env eq ty)
  shiftedSubstBinder c e m o s env eq (ShPi p ty) = ShPi (shiftedSubstPi c e m o s env eq p) (shiftedSubst c e m o s env eq ty)
  shiftedSubstBinder c e m o s env eq (ShPVar p ty) = ShPVar (shiftedSubstPi c e m o s env eq p) (shiftedSubst c e m o s env eq ty)
  shiftedSubstBinder c e m o s env eq (ShPLet v ty) = ShPLet (shiftedSubst c e m o s env eq v) (shiftedSubst c e m o s env eq ty)
  shiftedSubstBinder c e m o s env eq (ShPVTy ty) = ShPVTy (shiftedSubst c e m o s env eq ty)

  0 shiftedSubstPi : (c, e, m : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> (env : SubstEnv ds ws) ->
                     {0 p : PiInfo (Term vs)} -> {0 p' : PiInfo (Term (outer ++ (ds ++ ws)))} -> size o = c + e ->
                     PiShifted c (e + (size s + m)) p p' -> PiShifted c (e + m) p (substPi o s env p')
  shiftedSubstPi c e m o s env eq ShImplicit = ShImplicit
  shiftedSubstPi c e m o s env eq ShExplicit = ShExplicit
  shiftedSubstPi c e m o s env eq ShAutoImplicit = ShAutoImplicit
  shiftedSubstPi c e m o s env eq (ShDefault t) = ShDefault (shiftedSubst c e m o s env eq t)

mutual
  0 shiftedOnce : {0 w, w' : Term ys} -> Shifted c d v w -> Shifted c d v w' -> w = w'
  shiftedOnce (ShLocal a) (ShLocal a') = localsAt (shiftedAtOnce a a')
  shiftedOnce ShRef ShRef = Refl
  shiftedOnce (ShMeta ts) (ShMeta ts') = cong (Meta _ _ _) (allShiftedOnce ts ts')
  shiftedOnce (ShBind b sc) (ShBind b' sc') = cong2 (Bind _ _) (binderShiftedOnce b b') (shiftedOnce sc sc')
  shiftedOnce (ShApp f a) (ShApp f' a') = cong2 (App _) (shiftedOnce f f') (shiftedOnce a a')
  shiftedOnce (ShAs n t) (ShAs n' t') = cong2 (As _ _) (shiftedOnce n n') (shiftedOnce t t')
  shiftedOnce (ShDelayed t) (ShDelayed t') = cong (TDelayed _ _) (shiftedOnce t t')
  shiftedOnce (ShDelay ty a) (ShDelay ty' a') = cong2 (TDelay _ _) (shiftedOnce ty ty') (shiftedOnce a a')
  shiftedOnce (ShForce t) (ShForce t') = cong (TForce _ _) (shiftedOnce t t')
  shiftedOnce ShPrim ShPrim = Refl
  shiftedOnce ShPlaceholder ShPlaceholder = Refl
  shiftedOnce ShImpossible ShImpossible = Refl
  shiftedOnce (ShDotted t) (ShDotted t') = cong (\x => Erased _ (Dotted x)) (shiftedOnce t t')
  shiftedOnce ShType ShType = Refl

  0 allShiftedOnce : {0 ws, ws' : List (Term ys)} -> AllShifted c d vs' ws -> AllShifted c d vs' ws' -> ws = ws'
  allShiftedOnce ShNone ShNone = Refl
  allShiftedOnce (ShEach t ts) (ShEach t' ts') = cong2 (::) (shiftedOnce t t') (allShiftedOnce ts ts')

  0 binderShiftedOnce : {0 b1, b2 : Binder (Term ys)} -> BinderShifted c d b b1 -> BinderShifted c d b b2 -> b1 = b2
  binderShiftedOnce (ShLam p ty) (ShLam p' ty') = cong2 (Lam _ _) (piShiftedOnce p p') (shiftedOnce ty ty')
  binderShiftedOnce (ShLet v ty) (ShLet v' ty') = cong2 (Let _ _) (shiftedOnce v v') (shiftedOnce ty ty')
  binderShiftedOnce (ShPi p ty) (ShPi p' ty') = cong2 (Pi _ _) (piShiftedOnce p p') (shiftedOnce ty ty')
  binderShiftedOnce (ShPVar p ty) (ShPVar p' ty') = cong2 (PVar _ _) (piShiftedOnce p p') (shiftedOnce ty ty')
  binderShiftedOnce (ShPLet v ty) (ShPLet v' ty') = cong2 (PLet _ _) (shiftedOnce v v') (shiftedOnce ty ty')
  binderShiftedOnce (ShPVTy ty) (ShPVTy ty') = cong (PVTy _ _) (shiftedOnce ty ty')

  0 piShiftedOnce : {0 p1, p2 : PiInfo (Term ys)} -> PiShifted c d p p1 -> PiShifted c d p p2 -> p1 = p2
  piShiftedOnce ShImplicit ShImplicit = Refl
  piShiftedOnce ShExplicit ShExplicit = Refl
  piShiftedOnce ShAutoImplicit ShAutoImplicit = Refl
  piShiftedOnce (ShDefault t) (ShDefault t') = cong DefImplicit (shiftedOnce t t')

------------------------------------------------------------------------------
-- Maps commute with weakening, with values put in, and with embedding
------------------------------------------------------------------------------

0 insertLocal : (mv : LocalMove) -> (c : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                (0 p : IsVar n i (local ++ out1)) -> (0 q : IsVar m j (local ++ out2)) ->
                MovesLocal mv (size o + c) i j ->
                Mapped mv bs vals (size o + (size s + c)) (insertNames {outer = out1} o s (Local fc l i p)) (insertNames {outer = out2} o s (Local fc l j q))
insertLocal KeepsLocals c {out1} {out2} o s p q Refl =
  mappedLocals KeepsLocals (size o + (size s + c))
    (localAtIdx (insertNVarNames {outer = out1} o s (MkNVar p)))
    (localAtIdx (insertNVarNames {outer = out2} o s (MkNVar q)))
    (insertKeeps (size o) (size s) (insertNVarNamesIdx {outer = out1} o s (MkNVar p))
                                   (insertNVarNamesIdx {outer = out2} o s (MkNVar q)))
insertLocal DropsOne c {out1} {out2} o s p q d =
  mappedLocals DropsOne (size o + (size s + c))
    (localAtIdx (insertNVarNames {outer = out1} o s (MkNVar p)))
    (localAtIdx (insertNVarNames {outer = out2} o s (MkNVar q)))
    (insertDrops (size o) (size s) c d (insertNVarNamesIdx {outer = out1} o s (MkNVar p))
                                       (insertNVarNamesIdx {outer = out2} o s (MkNVar q)))

mutual
  -- A map commutes with weakening: a term mapped at a depth past the
  -- inserted variables' place, weakened, is its image weakened, mapped
  -- that many deeper.
  0 mappedInsert : (c : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                   {0 src : Term (local ++ out1)} -> {0 img : Term (local ++ out2)} ->
                   Mapped mv bs vals (size o + c) src img ->
                   Mapped mv bs vals (size o + (size s + c)) (insertNames {outer = out1} o s src) (insertNames {outer = out2} o s img)
  mappedInsert {mv} c o s (MLocal {p} {q} moved) = insertLocal mv c o s p q moved
  mappedInsert c o s (MMarker at sh) = MMarker at (shiftedInsert Z (size o) c o s Refl sh)
  mappedInsert c o s (MRef kept) = MRef kept
  mappedInsert c o s (MMeta none ts) = MMeta none (mappedInsertAll c o s ts)
  mappedInsert c o@(MkSizeOf _ _) s (MBind b sc) = MBind (mappedInsertBinder c o s b) (mappedInsert c (suc o) s sc)
  mappedInsert c o s (MApp f a) = MApp (mappedInsert c o s f) (mappedInsert c o s a)
  mappedInsert c o s (MAs n t) = MAs (mappedInsert c o s n) (mappedInsert c o s t)
  mappedInsert c o s (MDelayed t) = MDelayed (mappedInsert c o s t)
  mappedInsert c o s (MDelay ty a) = MDelay (mappedInsert c o s ty) (mappedInsert c o s a)
  mappedInsert c o s (MForce t) = MForce (mappedInsert c o s t)
  mappedInsert c o s MPrim = MPrim
  mappedInsert c o s MPlaceholder = MPlaceholder
  mappedInsert c o s MImpossible = MImpossible
  mappedInsert c o s (MDotted t) = MDotted (mappedInsert c o s t)
  mappedInsert c o s MType = MType

  0 mappedInsertAll : (c : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                      {0 srcs : List (Term (local ++ out1))} -> {0 imgs : List (Term (local ++ out2))} ->
                      AllMapped mv bs vals (size o + c) srcs imgs ->
                      AllMapped mv bs vals (size o + (size s + c)) (insertNamesTerms {outer = out1} o s srcs) (insertNamesTerms {outer = out2} o s imgs)
  mappedInsertAll c o s MNone = MNone
  mappedInsertAll c o s (MEach t ts) = MEach (mappedInsert c o s t) (mappedInsertAll c o s ts)

  0 mappedInsertBinder : (c : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                         {0 b : Binder (Term (local ++ out1))} -> {0 b' : Binder (Term (local ++ out2))} ->
                         BinderMapped mv bs vals (size o + c) b b' ->
                         BinderMapped mv bs vals (size o + (size s + c)) (insertNamesBinder {outer = out1} o s b) (insertNamesBinder {outer = out2} o s b')
  mappedInsertBinder c o s (MLam p ty) = MLam (mappedInsertPi c o s p) (mappedInsert c o s ty)
  mappedInsertBinder c o s (MLet v ty) = MLet (mappedInsert c o s v) (mappedInsert c o s ty)
  mappedInsertBinder c o s (MPi p ty) = MPi (mappedInsertPi c o s p) (mappedInsert c o s ty)
  mappedInsertBinder c o s (MPVar p ty) = MPVar (mappedInsertPi c o s p) (mappedInsert c o s ty)
  mappedInsertBinder c o s (MPLet v ty) = MPLet (mappedInsert c o s v) (mappedInsert c o s ty)
  mappedInsertBinder c o s (MPVTy ty) = MPVTy (mappedInsert c o s ty)

  0 mappedInsertPi : (c : Nat) -> (o : SizeOf local) -> (s : SizeOf new) ->
                     {0 p : PiInfo (Term (local ++ out1))} -> {0 p' : PiInfo (Term (local ++ out2))} ->
                     PiMapped mv bs vals (size o + c) p p' ->
                     PiMapped mv bs vals (size o + (size s + c)) (insertNamesPi {outer = out1} o s p) (insertNamesPi {outer = out2} o s p')
  mappedInsertPi c o s MImplicit = MImplicit
  mappedInsertPi c o s MExplicit = MExplicit
  mappedInsertPi c o s MAutoImplicit = MAutoImplicit
  mappedInsertPi c o s (MDefault t) = MDefault (mappedInsert c o s t)

-- A term mapped, weakened past one binder, is mapped one deeper.
0 mappedWeaken : (c : Nat) -> Mapped mv bs vals c a a' -> Mapped mv bs vals (S c) (weaken {nm} a) (weaken {nm} a')
mappedWeaken c m = mappedInsert c zero (suc zero) m

0 envMappedAt : EnvMapped mv bs vals c env env' -> (w : Var ds) -> Mapped mv bs vals c (Var.index env w) (Var.index env' w)
envMappedAt (EnvEach m _) (MkVar First) = m
envMappedAt (EnvEach _ ms) (MkVar (Later v)) = envMappedAt ms (MkVar v)
envMappedAt EnvNone (MkVar _) impossible

-- A local among the variables values are put in for, on both sides: the
-- value, weakened under the binders, mapped as the value is.
0 substMiddleMapped : (c : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> EnvMapped mv bs vals c env env' ->
                      (k : Nat) -> Nat.LT k (size s) ->
                      (0 p : IsVar n (size o + k) (outer ++ (ds ++ xs))) -> (0 q : IsVar m (size o + k) (outer ++ (ds ++ ys))) ->
                      Mapped mv bs vals (size o + c)
                             (substTerm o s env (Local fc l (size o + k) p)) (substTerm o s env' (Local fc l (size o + k) q))
substMiddleMapped c {env} {env'} {fc} {l} o s envm k lt p q = case varAt s k lt of
  (w ** at) =>
    rewrite substMiddle {fc} {r = l} o s env p w (cong (size o +) (sym at)) in
    rewrite substMiddle {fc} {r = l} o s env' q w (cong (size o +) (sym at)) in
    mappedInsert c zero o (envMappedAt envm w)

0 substLocal : (mv : LocalMove) -> (c : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> EnvMapped mv bs vals c env env' ->
               (0 p : IsVar n i (outer ++ (ds ++ xs))) -> (0 q : IsVar m j (outer ++ (ds ++ ys))) ->
               MovesLocal mv (size o + (size s + c)) i j ->
               Mapped mv bs vals (size o + c) (substTerm o s env (Local fc l i p)) (substTerm o s env' (Local fc l j q))
substLocal KeepsLocals c {env} {env'} {i} o s envm p q Refl = case range (size o) (size s) i of
  InFirst lt => mappedLocals KeepsLocals (size o + c) (substBelow o s env p lt) (substBelow o s env' q lt) Refl
  InSecond k eq lt => case eq of
    Refl => substMiddleMapped c o s envm k lt p q
  PastBoth k eq => mappedLocals KeepsLocals (size o + c) (substPast o s env p k eq) (substPast o s env' q k eq) Refl
substLocal DropsOne c {env} {env'} {i} o s envm p q d = case range (size o) (size s) i of
  InFirst lt => case droppedBelowCut (size o) (size s + c) lt d of
    Refl => mappedLocals DropsOne (size o + c) (substBelow o s env p lt) (substBelow o s env' q lt)
                         (droppedBelow (transitive lt (lteAddRight {m = c} (size o))))
  InSecond k eq lt => case eq of
    Refl => case droppedPeel (size o) (size s + c) k d of
      (k1 ** (Refl, d1)) => case droppedBelowCut (size s) c lt d1 of
        Refl => substMiddleMapped c o s envm k lt p q
  PastBoth k eq => case eq of
    Refl => case droppedPeel (size o) (size s + c) (size s + k) d of
      (k1 ** (Refl, d1)) => case droppedPeel (size s) c k d1 of
        (k' ** (Refl, d')) =>
          mappedLocals DropsOne (size o + c) (substPast o s env p k Refl) (substPast o s env' q k' Refl)
                       (droppedUnder (size o) d')

mutual
  -- A map commutes with putting values in: a term mapped at a depth past
  -- the variables values are put in for, given those values, is its image
  -- given theirs, mapped as many shallower.
  0 mappedSubst : (c : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> EnvMapped mv bs vals c env env' ->
                  {0 src : Term (outer ++ (ds ++ xs))} -> {0 img : Term (outer ++ (ds ++ ys))} ->
                  Mapped mv bs vals (size o + (size s + c)) src img ->
                  Mapped mv bs vals (size o + c) (substTerm o s env src) (substTerm o s env' img)
  mappedSubst {mv} c o s envm (MLocal {p} {q} moved) = substLocal mv c o s envm p q moved
  mappedSubst {env'} c o s envm (MMarker at sh) = MMarker at (shiftedSubst Z (size o) c o s env' Refl sh)
  mappedSubst c o s envm (MRef kept) = MRef kept
  mappedSubst c o s envm (MMeta none ts) = MMeta none (mappedSubstAll c o s envm ts)
  mappedSubst c o@(MkSizeOf _ _) s envm (MBind b sc) = MBind (mappedSubstBinder c o s envm b) (mappedSubst c (suc o) s envm sc)
  mappedSubst c o s envm (MApp f a) = MApp (mappedSubst c o s envm f) (mappedSubst c o s envm a)
  mappedSubst c o s envm (MAs n t) = MAs (mappedSubst c o s envm n) (mappedSubst c o s envm t)
  mappedSubst c o s envm (MDelayed t) = MDelayed (mappedSubst c o s envm t)
  mappedSubst c o s envm (MDelay ty a) = MDelay (mappedSubst c o s envm ty) (mappedSubst c o s envm a)
  mappedSubst c o s envm (MForce t) = MForce (mappedSubst c o s envm t)
  mappedSubst c o s envm MPrim = MPrim
  mappedSubst c o s envm MPlaceholder = MPlaceholder
  mappedSubst c o s envm MImpossible = MImpossible
  mappedSubst c o s envm (MDotted t) = MDotted (mappedSubst c o s envm t)
  mappedSubst c o s envm MType = MType

  0 mappedSubstAll : (c : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> EnvMapped mv bs vals c env env' ->
                     {0 srcs : List (Term (outer ++ (ds ++ xs)))} -> {0 imgs : List (Term (outer ++ (ds ++ ys)))} ->
                     AllMapped mv bs vals (size o + (size s + c)) srcs imgs ->
                     AllMapped mv bs vals (size o + c) (substTerms o s env srcs) (substTerms o s env' imgs)
  mappedSubstAll c o s envm MNone = MNone
  mappedSubstAll c o s envm (MEach t ts) = MEach (mappedSubst c o s envm t) (mappedSubstAll c o s envm ts)

  0 mappedSubstBinder : (c : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> EnvMapped mv bs vals c env env' ->
                        {0 b : Binder (Term (outer ++ (ds ++ xs)))} -> {0 b' : Binder (Term (outer ++ (ds ++ ys)))} ->
                        BinderMapped mv bs vals (size o + (size s + c)) b b' ->
                        BinderMapped mv bs vals (size o + c) (substBinder o s env b) (substBinder o s env' b')
  mappedSubstBinder c o s envm (MLam p ty) = MLam (mappedSubstPi c o s envm p) (mappedSubst c o s envm ty)
  mappedSubstBinder c o s envm (MLet v ty) = MLet (mappedSubst c o s envm v) (mappedSubst c o s envm ty)
  mappedSubstBinder c o s envm (MPi p ty) = MPi (mappedSubstPi c o s envm p) (mappedSubst c o s envm ty)
  mappedSubstBinder c o s envm (MPVar p ty) = MPVar (mappedSubstPi c o s envm p) (mappedSubst c o s envm ty)
  mappedSubstBinder c o s envm (MPLet v ty) = MPLet (mappedSubst c o s envm v) (mappedSubst c o s envm ty)
  mappedSubstBinder c o s envm (MPVTy ty) = MPVTy (mappedSubst c o s envm ty)

  0 mappedSubstPi : (c : Nat) -> (o : SizeOf outer) -> (s : SizeOf ds) -> EnvMapped mv bs vals c env env' ->
                    {0 p : PiInfo (Term (outer ++ (ds ++ xs)))} -> {0 p' : PiInfo (Term (outer ++ (ds ++ ys)))} ->
                    PiMapped mv bs vals (size o + (size s + c)) p p' ->
                    PiMapped mv bs vals (size o + c) (substPi o s env p) (substPi o s env' p')
  mappedSubstPi c o s envm MImplicit = MImplicit
  mappedSubstPi c o s envm MExplicit = MExplicit
  mappedSubstPi c o s envm MAutoImplicit = MAutoImplicit
  mappedSubstPi c o s envm (MDefault t) = MDefault (mappedSubst c o s envm t)

mutual
  -- A term over a scope, embedded past it, is mapped to itself embedded
  -- past another, at any depth past the scope, where it names none of the
  -- names the map replaces: every local is below the depth.
  0 mappedEmbed : (c : Nat) -> (s : SizeOf zs) -> (t : Term zs) -> mentions BoundOrUnknown bs t = False ->
                  Mapped mv bs vals (size s + c) (embedTerm {outer = xs} t) (embedTerm {outer = ys} t)
  mappedEmbed {mv} c s (Local fc l i p) _ =
    MLocal (movesBelow mv (transitive (varBelowSize s (MkVar p)) (lteAddRight {m = c} (size s))))
  mappedEmbed {bs} c s (Ref fc Bound n) none = MRef (noneAt bs none)
  mappedEmbed c s (Ref fc Func n) _ = MRef ()
  mappedEmbed c s (Ref fc (DataCon tag arity) n) _ = MRef ()
  mappedEmbed c s (Ref fc (TyCon arity) n) _ = MRef ()
  mappedEmbed {bs} c s (Meta fc m k args) none =
    MMeta (noneAt bs (fst (orFalse (replaces bs m) none))) (mappedEmbedAll c s args (snd (orFalse (replaces bs m) none)))
  mappedEmbed {bs} c s@(MkSizeOf _ _) (Bind fc x b sc) none =
    MBind (mappedEmbedBinder c s b (fst (orFalse (mentionsInBinder BoundOrUnknown bs b) none)))
          (mappedEmbed c (suc s) sc (snd (orFalse (mentionsInBinder BoundOrUnknown bs b) none)))
  mappedEmbed {bs} c s (App fc f a) none =
    MApp (mappedEmbed c s f (fst (orFalse (mentions BoundOrUnknown bs f) none)))
         (mappedEmbed c s a (snd (orFalse (mentions BoundOrUnknown bs f) none)))
  mappedEmbed {bs} c s (As fc side n t) none =
    MAs (mappedEmbed c s n (fst (orFalse (mentions BoundOrUnknown bs n) none)))
        (mappedEmbed c s t (snd (orFalse (mentions BoundOrUnknown bs n) none)))
  mappedEmbed c s (TDelayed fc r t) none = MDelayed (mappedEmbed c s t none)
  mappedEmbed {bs} c s (TDelay fc r ty a) none =
    MDelay (mappedEmbed c s ty (fst (orFalse (mentions BoundOrUnknown bs ty) none)))
           (mappedEmbed c s a (snd (orFalse (mentions BoundOrUnknown bs ty) none)))
  mappedEmbed c s (TForce fc r t) none = MForce (mappedEmbed c s t none)
  mappedEmbed c s (PrimVal fc k) _ = MPrim
  mappedEmbed c s (Erased fc Placeholder) _ = MPlaceholder
  mappedEmbed c s (Erased fc Impossible) _ = MImpossible
  mappedEmbed c s (Erased fc (Dotted t)) none = MDotted (mappedEmbed c s t none)
  mappedEmbed c s (TType fc u) _ = MType

  0 mappedEmbedAll : (c : Nat) -> (s : SizeOf zs) -> (ts : List (Term zs)) -> mentionsIn BoundOrUnknown bs ts = False ->
                     AllMapped mv bs vals (size s + c) (embedTerms {outer = xs} ts) (embedTerms {outer = ys} ts)
  mappedEmbedAll c s [] _ = MNone
  mappedEmbedAll {bs} c s (t :: ts) none =
    MEach (mappedEmbed c s t (fst (orFalse (mentions BoundOrUnknown bs t) none)))
          (mappedEmbedAll c s ts (snd (orFalse (mentions BoundOrUnknown bs t) none)))

  0 mappedEmbedBinder : (c : Nat) -> (s : SizeOf zs) -> (b : Binder (Term zs)) -> mentionsInBinder BoundOrUnknown bs b = False ->
                        BinderMapped mv bs vals (size s + c) (embedBinder {outer = xs} b) (embedBinder {outer = ys} b)
  mappedEmbedBinder {bs} c s (Lam fc r p ty) none =
    MLam (mappedEmbedPi c s p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
         (mappedEmbed c s ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  mappedEmbedBinder {bs} c s (Let fc r v ty) none =
    MLet (mappedEmbed c s v (fst (orFalse (mentions BoundOrUnknown bs v) none)))
         (mappedEmbed c s ty (snd (orFalse (mentions BoundOrUnknown bs v) none)))
  mappedEmbedBinder {bs} c s (Pi fc r p ty) none =
    MPi (mappedEmbedPi c s p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
        (mappedEmbed c s ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  mappedEmbedBinder {bs} c s (PVar fc r p ty) none =
    MPVar (mappedEmbedPi c s p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
          (mappedEmbed c s ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  mappedEmbedBinder {bs} c s (PLet fc r v ty) none =
    MPLet (mappedEmbed c s v (fst (orFalse (mentions BoundOrUnknown bs v) none)))
          (mappedEmbed c s ty (snd (orFalse (mentions BoundOrUnknown bs v) none)))
  mappedEmbedBinder c s (PVTy fc r ty) none = MPVTy (mappedEmbed c s ty none)

  0 mappedEmbedPi : (c : Nat) -> (s : SizeOf zs) -> (p : PiInfo (Term zs)) -> mentionsInPi BoundOrUnknown bs p = False ->
                    PiMapped mv bs vals (size s + c) (embedPi {outer = xs} p) (embedPi {outer = ys} p)
  mappedEmbedPi c s Implicit _ = MImplicit
  mappedEmbedPi c s Explicit _ = MExplicit
  mappedEmbedPi c s AutoImplicit _ = MAutoImplicit
  mappedEmbedPi c s (DefImplicit t) none = MDefault (mappedEmbed c s t none)

------------------------------------------------------------------------------
-- A map gives one image
------------------------------------------------------------------------------

0 laterOnce : {0 v : IsVar n i xs} -> {0 v' : IsVar n' i' xs} -> MkVar v = MkVar v' ->
              MkVar {vars = y :: xs} (Later v) = MkVar (Later v')
laterOnce Refl = Refl

-- A name is at the first bound that replaces it in one way.
0 firstAtOnce : FirstAt bs w n -> FirstAt bs w' n -> w = w'
firstAtOnce (AtHere _) (AtHere _) = Refl
firstAtOnce (AtHere here) (AtLater later _) = absurd (trans (sym here) later)
firstAtOnce (AtLater later _) (AtHere here) = absurd (trans (sym here) later)
firstAtOnce (AtLater _ first) (AtLater _ first') = laterOnce (firstAtOnce first first')

-- A name a bound replaces is replaced.
0 firstNotNone : FirstAt bs w n -> NoneAt bs n -> Void
firstNotNone (AtHere here) (NotThis differs _) = absurd (trans (sym here) differs)
firstNotNone (AtLater _ first) (NotThis _ none) = firstNotNone first none

mutual
  0 mappedOnce : {0 u, u' : Term ys} -> Mapped mv bs vals c t u -> Mapped mv bs vals c t u' -> u = u'
  mappedOnce {mv} (MLocal moved) (MLocal moved') = localsAt (movesOnce mv moved moved')
  mappedOnce (MMarker at sh) (MMarker at' sh') = case firstAtOnce at at' of
    Refl => shiftedOnce sh sh'
  mappedOnce (MMarker at _) (MRef kept) = void (firstNotNone at kept)
  mappedOnce (MRef kept) (MMarker at _) = void (firstNotNone at kept)
  mappedOnce (MRef _) (MRef _) = Refl
  mappedOnce (MMeta _ xs) (MMeta _ xs') = cong (Meta _ _ _) (allMappedOnce xs xs')
  mappedOnce (MBind b sc) (MBind b' sc') = cong2 (Bind _ _) (binderMappedOnce b b') (mappedOnce sc sc')
  mappedOnce (MApp f a) (MApp f' a') = cong2 (App _) (mappedOnce f f') (mappedOnce a a')
  mappedOnce (MAs n x) (MAs n' x') = cong2 (As _ _) (mappedOnce n n') (mappedOnce x x')
  mappedOnce (MDelayed x) (MDelayed x') = cong (TDelayed _ _) (mappedOnce x x')
  mappedOnce (MDelay ty a) (MDelay ty' a') = cong2 (TDelay _ _) (mappedOnce ty ty') (mappedOnce a a')
  mappedOnce (MForce x) (MForce x') = cong (TForce _ _) (mappedOnce x x')
  mappedOnce MPrim MPrim = Refl
  mappedOnce MPlaceholder MPlaceholder = Refl
  mappedOnce MImpossible MImpossible = Refl
  mappedOnce (MDotted x) (MDotted x') = cong (\y => Erased _ (Dotted y)) (mappedOnce x x')
  mappedOnce MType MType = Refl

  0 allMappedOnce : {0 us, us' : List (Term ys)} -> AllMapped mv bs vals c ts us -> AllMapped mv bs vals c ts us' -> us = us'
  allMappedOnce MNone MNone = Refl
  allMappedOnce (MEach x xs) (MEach x' xs') = cong2 (::) (mappedOnce x x') (allMappedOnce xs xs')

  0 binderMappedOnce : {0 b1, b2 : Binder (Term ys)} -> BinderMapped mv bs vals c b b1 -> BinderMapped mv bs vals c b b2 -> b1 = b2
  binderMappedOnce (MLam p ty) (MLam p' ty') = cong2 (Lam _ _) (piMappedOnce p p') (mappedOnce ty ty')
  binderMappedOnce (MLet v ty) (MLet v' ty') = cong2 (Let _ _) (mappedOnce v v') (mappedOnce ty ty')
  binderMappedOnce (MPi p ty) (MPi p' ty') = cong2 (Pi _ _) (piMappedOnce p p') (mappedOnce ty ty')
  binderMappedOnce (MPVar p ty) (MPVar p' ty') = cong2 (PVar _ _) (piMappedOnce p p') (mappedOnce ty ty')
  binderMappedOnce (MPLet v ty) (MPLet v' ty') = cong2 (PLet _ _) (mappedOnce v v') (mappedOnce ty ty')
  binderMappedOnce (MPVTy ty) (MPVTy ty') = cong (PVTy _ _) (mappedOnce ty ty')

  0 piMappedOnce : {0 p1, p2 : PiInfo (Term ys)} -> PiMapped mv bs vals c p p1 -> PiMapped mv bs vals c p p2 -> p1 = p2
  piMappedOnce MImplicit MImplicit = Refl
  piMappedOnce MExplicit MExplicit = Refl
  piMappedOnce MAutoImplicit MAutoImplicit = Refl
  piMappedOnce (MDefault t) (MDefault t') = cong DefImplicit (mappedOnce t t')

------------------------------------------------------------------------------
-- What a map keeps of the forms the evaluator reads
------------------------------------------------------------------------------

0 allMappedLength : AllMapped mv bs vals c ts us -> length ts = length us
allMappedLength MNone = Refl
allMappedLength (MEach _ ms) = cong S (allMappedLength ms)

0 sameLength : AllMapped mv bs vals c ts us -> length ts = k -> length us = k
sameLength ms same = trans (sym (allMappedLength ms)) same

0 allMappedSnoc : AllMapped mv bs vals c ts us -> Mapped mv bs vals c t u ->
                  AllMapped mv bs vals c (ts ++ [t]) (us ++ [u])
allMappedSnoc MNone m = MEach m MNone
allMappedSnoc (MEach m0 ms) m = MEach m0 (allMappedSnoc ms m)

0 allMappedAppend : AllMapped mv bs vals c ts us -> AllMapped mv bs vals c ts' us' ->
                    AllMapped mv bs vals c (ts ++ ts') (us ++ us')
allMappedAppend MNone ms' = ms'
allMappedAppend (MEach m ms) ms' = MEach m (allMappedAppend ms ms')

-- Terms mapped, read as two runs: the images of each run.
0 allMappedSplit : (pre, post : List (Term xs)) -> ts = pre ++ post -> AllMapped mv bs vals c ts us ->
                   (us1 : List (Term ys) ** (us2 : List (Term ys) **
                     (us = us1 ++ us2, AllMapped mv bs vals c pre us1, AllMapped mv bs vals c post us2)))
allMappedSplit {us} [] post Refl ms = ([] ** (us ** (Refl, MNone, ms)))
allMappedSplit (t :: pre) post Refl (MEach {u} m ms) = case allMappedSplit pre post Refl ms of
  (us1 ** (us2 ** (same, ms1, ms2))) => (u :: us1 ** (us2 ** (cong (u ::) same, MEach m ms1, ms2)))

0 mappedArguments : AllMapped mv bs vals c args args' -> (names : Scope) ->
                    (same : length args = length names) -> (same' : length args' = length names) ->
                    EnvMapped mv bs vals c (bindArguments args names same) (bindArguments args' names same')
mappedArguments MNone [] _ _ = EnvNone
mappedArguments (MEach m ms) (n :: names) same same' =
  EnvEach m (mappedArguments ms names (cong pred same) (cong pred same'))
mappedArguments MNone (_ :: _) Refl _ impossible
mappedArguments (MEach _ _) [] Refl _ impossible

0 mappedFields : AllMapped mv bs vals c fields fields' -> (names : List Name) ->
                 (same : length fields = length names) -> (same' : length fields' = length names) ->
                 EnvMapped mv bs vals c env env' ->
                 EnvMapped mv bs vals c (bindFields fields names same env) (bindFields fields' names same' env')
mappedFields MNone [] _ _ envm = envm
mappedFields (MEach m ms) (n :: names) same same' envm =
  EnvEach m (mappedFields ms names (cong pred same) (cong pred same') envm)
mappedFields MNone (_ :: _) Refl _ _ impossible
mappedFields (MEach _ _) [] Refl _ _ impossible

0 mappedApply : Mapped mv bs vals c v v' -> AllMapped mv bs vals c rest rest' ->
                Mapped mv bs vals c (apply fc v rest) (apply fc v' rest')
mappedApply m MNone = m
mappedApply m (MEach a ms) = mappedApply (MApp m a) ms

-- A head and its arguments, mapped: the image's head and arguments.
0 mappedSpine : Mapped mv bs vals c t t' -> Spine t h args ->
                (h' : Term ys ** (args' : List (Term ys) **
                  (Spine t' h' args', Mapped mv bs vals c h h', AllMapped mv bs vals c args args')))
mappedSpine {t'} m Head = (t' ** ([] ** (Head, m, MNone)))
mappedSpine (MApp {a'} mf ma) (Applied s) = case mappedSpine mf s of
  (h' ** (args' ** (s', mh, margs))) => (h' ** (args' ++ [a'] ** (Applied s', mh, allMappedSnoc margs ma)))

0 spineAt : Spine t h args -> h = h' -> Spine t h' args
spineAt s Refl = s

-- A map keeps a reference to a function, a constructor or a family.
0 funcImage : Mapped mv bs vals c (Ref fc Func n) h' -> h' = Ref fc Func n
funcImage (MRef _) = Refl

0 conImage : Mapped mv bs vals c (Ref fc (DataCon tag arity) n) h' -> h' = Ref fc (DataCon tag arity) n
conImage (MRef _) = Refl

0 familyImage : Mapped mv bs vals c (Ref fc (TyCon arity) n) h' -> h' = Ref fc (TyCon arity) n
familyImage (MRef _) = Refl

-- A map keeps an unknown, its arguments mapped, where it is not one the
-- bounds name.
0 metaImage : Mapped mv bs vals c (Meta fc m k ts) h' ->
              (us : List (Term ys) ** (h' = Meta fc m k us, AllMapped mv bs vals c ts us, NoneAt bs m))
metaImage (MMeta none ms) = (_ ** (Refl, ms, none))

0 consKept : (m, m' : Maybe (Vect k Constant)) -> ((xs : Vect k Constant) -> m = Just xs -> m' = Just xs) ->
             map (c ::) m = Just cs -> map (c ::) m' = Just cs
consKept (Just cs') m' keep same = rewrite keep cs' Refl in same
consKept Nothing m' keep same = void (nothingIsJust same)

-- A map keeps every constant, so the constants of a primitive's arguments.
0 mappedConstants : {n : Nat} -> AllMapped mv bs vals c ts us -> constantsOf n ts = Just cs -> constantsOf n us = Just cs
mappedConstants {n = Z} MNone same = same
mappedConstants {n = Z} (MEach _ _) same = void (nothingIsJust same)
mappedConstants {n = S k} MNone same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach {ts = ts'} {us = us'} MPrim ms) same =
  consKept (constantsOf k ts') (constantsOf k us') (\cs', found => mappedConstants ms found) same
mappedConstants {n = S k} (MEach (MLocal _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MMarker _ _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MRef _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MMeta _ _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MBind _ _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MApp _ _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MAs _ _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MDelayed _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MDelay _ _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MForce _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach MPlaceholder _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach MImpossible _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach (MDotted _) _) same = void (nothingIsJust same)
mappedConstants {n = S k} (MEach MType _) same = void (nothingIsJust same)

0 mappedCoercible : Mapped mv bs vals c v v' -> Coercible v -> Coercible v'
mappedCoercible m (CoercesConstructor s) = case mappedSpine m s of
  (h' ** (_ ** (s', mh, _))) => CoercesConstructor (spineAt s' (conImage mh))
mappedCoercible m (CoercesFamily s) = case mappedSpine m s of
  (h' ** (_ ** (s', mh, _))) => CoercesFamily (spineAt s' (familyImage mh))
mappedCoercible MPrim CoercesConstant = CoercesConstant
mappedCoercible MType CoercesUniverse = CoercesUniverse

0 mappedComputes : AllMapped mv bs vals c args args' -> Computes running op args v ->
                   (v' : Term ys ** (Mapped mv bs vals c v v', Computes running op args' v'))
mappedComputes margs (OnConstants consts table) = (_ ** (MPrim, OnConstants (mappedConstants margs consts) table))
mappedComputes (MEach _ (MEach _ (MEach m MNone))) (BelievedMe coerces) = (_ ** (m, BelievedMe (mappedCoercible m coerces)))

0 mappedDrops : Mapped mv bs vals c f f' -> DropsArguments f -> DropsArguments f'
mappedDrops MPlaceholder DropsAtPlaceholder = DropsAtPlaceholder
mappedDrops MImpossible DropsAtImpossible = DropsAtImpossible
mappedDrops MPrim DropsAtConstant = DropsAtConstant
mappedDrops MType DropsAtUniverse = DropsAtUniverse
mappedDrops (MDelay _ _) DropsAtDelay = DropsAtDelay

0 mappedFloats : BinderMapped mv bs vals c b b' -> Floats ev b -> Floats ev b'
mappedFloats (MPi _ _) PiFloats = PiFloats
mappedFloats (MPVar _ _) PVarFloats = PVarFloats
mappedFloats (MPLet _ _) PLetFloats = PLetFloats
mappedFloats (MPVTy _) PVTyFloats = PVTyFloats
mappedFloats (MLet _ _) (LetFloats holes) = LetFloats holes

0 mappedShows : Mapped mv bs vals c t t' -> Shows t s -> (s' : Term ys ** (Mapped mv bs vals c s s', Shows t' s'))
mappedShows {t'} m Itself = (t' ** (m, Itself))
mappedShows (MDotted m) (ThroughDot shows) = case mappedShows m shows of
  (s' ** (ms, shows')) => (s' ** (ms, ThroughDot shows'))

0 mappedConcrete : Mapped mv bs vals c s s' -> Concrete s -> Concrete s'
mappedConcrete m (IsConstructor sp) = case mappedSpine m sp of
  (h' ** (_ ** (sp', mh, _))) => IsConstructor (spineAt sp' (conImage mh))
mappedConcrete m (IsFamily sp) = case mappedSpine m sp of
  (h' ** (_ ** (sp', mh, _))) => IsFamily (spineAt sp' (familyImage mh))
mappedConcrete MPrim IsConstant = IsConstant
mappedConcrete (MBind _ _) IsBinder = IsBinder
mappedConcrete MType IsUniverseValue = IsUniverseValue
mappedConcrete (MDelay _ _) IsDelay = IsDelay

0 mappedMisses : Mapped mv bs vals c s s' -> Misses ctx s alt -> Misses ctx s' alt
mappedMisses m (OtherTag sp differ) = case mappedSpine m sp of
  (h' ** (_ ** (sp', mh, _))) => OtherTag (spineAt sp' (conImage mh)) differ
mappedMisses m (OtherFamily sp apart) = case mappedSpine m sp of
  (h' ** (_ ** (sp', mh, _))) => OtherFamily (spineAt sp' (familyImage mh)) apart
mappedMisses MPrim (OtherPrimitiveType no) = OtherPrimitiveType no
mappedMisses MPrim PrimitiveFields = PrimitiveFields
mappedMisses MType (NotTheUniverse no) = NotTheUniverse no
mappedMisses MType UniverseFields = UniverseFields
mappedMisses (MBind (MPi _ _) _) (NotTheArrow no) = NotTheArrow no
mappedMisses (MBind (MPi _ _) _) (ArrowFields no) = ArrowFields no
mappedMisses MPrim (OtherConstant no) = OtherConstant no

------------------------------------------------------------------------------
-- Reduction is closed under every map
------------------------------------------------------------------------------

mutual
  ||| Reduction is closed under every map of terms: where a term reduces,
  ||| its image reduces, by the steps the term's take, to the image of what
  ||| the term reduces to. No step reads a bound reference, nor a local but
  ||| by its index: each step of a term is a step of its image, and what a
  ||| step puts in (a value for a variable, a leaf of a definition, which
  ||| names no name the map replaces) is mapped as the map's image of it.
  export
  0 mappedReduces : FreshIn ctx bs -> Mapped mv bs vals c t t' -> Reduces ev ctx t u ->
                    (u' : Term ys ** (Mapped mv bs vals c u u', Reduces ev ctx t' u'))
  mappedReduces fresh m (Then r1 r2) = case mappedReduces fresh m r1 of
    (u1 ** (m1, s1)) => case mappedReduces fresh m1 r2 of
      (u2 ** (m2, s2)) => (u2 ** (m2, Then s1 s2))
  mappedReduces fresh m (Contract k) = case mappedContracts fresh m k of
    (u' ** (mu, k')) => (u' ** (mu, Contract k'))
  mappedReduces fresh (MLocal {q} moved) (ALocal {fc'} {l'}) = (Local fc' l' _ q ** (MLocal moved, ALocal))
  mappedReduces fresh (MRef kept) (ARef {fc'}) = (_ ** (MRef {fc = fc'} kept, ARef))
  mappedReduces fresh (MMarker {t' = img} at sh) ARef = (img ** (MMarker at sh, reducesToItself img))
  mappedReduces fresh (MMeta none ms) (AMeta rs) = case mappedAllReduce fresh ms rs of
    (us' ** (ms', rs')) => (_ ** (MMeta none ms', AMeta rs'))
  mappedReduces fresh (MBind mb msc) (ABind rb rsc) = case mappedBinderReduces fresh mb rb of
    (b' ** (mb', rb')) => case mappedReduces fresh msc rsc of
      (sc' ** (msc', rsc')) => (_ ** (MBind mb' msc', ABind rb' rsc'))
  mappedReduces fresh (MApp mf ma) (AnApp rf ra) = case mappedReduces fresh mf rf of
    (f' ** (mf', rf')) => case mappedReduces fresh ma ra of
      (a' ** (ma', ra')) => (_ ** (MApp mf' ma', AnApp rf' ra'))
  mappedReduces fresh (MAs mn mt) (AnAs rn rt) = case mappedReduces fresh mn rn of
    (n' ** (mn', rn')) => case mappedReduces fresh mt rt of
      (t'' ** (mt', rt')) => (_ ** (MAs mn' mt', AnAs rn' rt'))
  mappedReduces fresh (MDelayed mt) (ADelayed rt) = case mappedReduces fresh mt rt of
    (t'' ** (mt', rt')) => (_ ** (MDelayed mt', ADelayed rt'))
  mappedReduces fresh (MDelay mty ma) (ADelay rty ra) = case mappedReduces fresh mty rty of
    (ty' ** (mty', rty')) => case mappedReduces fresh ma ra of
      (a' ** (ma', ra')) => (_ ** (MDelay mty' ma', ADelay rty' ra'))
  mappedReduces fresh (MForce mt) (AForce rt) = case mappedReduces fresh mt rt of
    (t'' ** (mt', rt')) => (_ ** (MForce mt', AForce rt'))
  mappedReduces fresh MPrim (APrimVal {fc'}) = (_ ** (MPrim {fc = fc'}, APrimVal))
  mappedReduces fresh MPlaceholder (AnErased {fc'} APlaceholder) = (_ ** (MPlaceholder {fc = fc'}, AnErased APlaceholder))
  mappedReduces fresh MImpossible (AnErased {fc'} AnImpossible) = (_ ** (MImpossible {fc = fc'}, AnErased AnImpossible))
  mappedReduces fresh (MDotted mt) (AnErased (ADotted rt)) = case mappedReduces fresh mt rt of
    (t'' ** (mt', rt')) => (_ ** (MDotted mt', AnErased (ADotted rt')))
  mappedReduces fresh MType (AType {fc'}) = (_ ** (MType {fc = fc'}, AType))

  0 mappedAllReduce : FreshIn ctx bs -> AllMapped mv bs vals c ts ts' -> AllReduce ev ctx ts us ->
                      (us' : List (Term ys) ** (AllMapped mv bs vals c us us', AllReduce ev ctx ts' us'))
  mappedAllReduce fresh MNone NoneLeft = ([] ** (MNone, NoneLeft))
  mappedAllReduce fresh (MEach m ms) (Each r rs) = case mappedReduces fresh m r of
    (u' ** (mu, r')) => case mappedAllReduce fresh ms rs of
      (us' ** (mus, rs')) => (u' :: us' ** (MEach mu mus, Each r' rs'))

  0 mappedBinderReduces : FreshIn ctx bs -> BinderMapped mv bs vals c b b' -> BinderReduces ev ctx b d ->
                          (d' : Binder (Term ys) ** (BinderMapped mv bs vals c d d', BinderReduces ev ctx b' d'))
  mappedBinderReduces fresh (MLam mp mty) (ALam rp rty) = case mappedPiReduces fresh mp rp of
    (p' ** (mp', rp')) => case mappedReduces fresh mty rty of
      (ty' ** (mty', rty')) => (_ ** (MLam mp' mty', ALam rp' rty'))
  mappedBinderReduces fresh (MLet mv' mty) (ALet rv rty) = case mappedReduces fresh mv' rv of
    (v' ** (mv'', rv')) => case mappedReduces fresh mty rty of
      (ty' ** (mty', rty')) => (_ ** (MLet mv'' mty', ALet rv' rty'))
  mappedBinderReduces fresh (MPi mp mty) (APi rp rty) = case mappedPiReduces fresh mp rp of
    (p' ** (mp', rp')) => case mappedReduces fresh mty rty of
      (ty' ** (mty', rty')) => (_ ** (MPi mp' mty', APi rp' rty'))
  mappedBinderReduces fresh (MPVar mp mty) (APVar rp rty) = case mappedPiReduces fresh mp rp of
    (p' ** (mp', rp')) => case mappedReduces fresh mty rty of
      (ty' ** (mty', rty')) => (_ ** (MPVar mp' mty', APVar rp' rty'))
  mappedBinderReduces fresh (MPLet mv' mty) (APLet rv rty) = case mappedReduces fresh mv' rv of
    (v' ** (mv'', rv')) => case mappedReduces fresh mty rty of
      (ty' ** (mty', rty')) => (_ ** (MPLet mv'' mty', APLet rv' rty'))
  mappedBinderReduces fresh (MPVTy mty) (APVTy rty) = case mappedReduces fresh mty rty of
    (ty' ** (mty', rty')) => (_ ** (MPVTy mty', APVTy rty'))

  0 mappedPiReduces : FreshIn ctx bs -> PiMapped mv bs vals c p p' -> PiReduces ev ctx p q ->
                      (q' : PiInfo (Term ys) ** (PiMapped mv bs vals c q q', PiReduces ev ctx p' q'))
  mappedPiReduces fresh MImplicit AnImplicit = (_ ** (MImplicit, AnImplicit))
  mappedPiReduces fresh MExplicit AnExplicit = (_ ** (MExplicit, AnExplicit))
  mappedPiReduces fresh MAutoImplicit AnAutoImplicit = (_ ** (MAutoImplicit, AnAutoImplicit))
  mappedPiReduces fresh (MDefault m) (ADefImplicit r) = case mappedReduces fresh m r of
    (t'' ** (mt, r')) => (_ ** (MDefault mt, ADefImplicit r'))

  0 mappedContracts : FreshIn ctx bs -> Mapped mv bs vals c t t' -> Contracts ev ctx t u ->
                      (u' : Term ys ** (Mapped mv bs vals c u u', Contracts ev ctx t' u'))
  mappedContracts {c} fresh (MApp (MBind (MLam _ _) msc) ma) Beta =
    (_ ** (mappedSubst c zero (suc zero) (EnvEach ma EnvNone) msc, Beta))
  mappedContracts {c} fresh (MBind (MLet mval _) msc) (Zeta runs) =
    (_ ** (mappedSubst c zero (suc zero) (EnvEach mval EnvNone) msc, Zeta runs))
  mappedContracts fresh m (Unfold {ns} spine defines admits isDef evaluates held same chooses) =
    case mappedSpine m spine of
      (h' ** (args' ** (spine', mh, margs))) =>
        case mappedChooses fresh (fresh defines isDef held) (mappedArguments margs ns same (sameLength margs same)) chooses of
          (v' ** (mv', chooses')) =>
            (v' ** (mv', Unfold (spineAt spine' (funcImage mh)) defines admits isDef evaluates held
                                (sameLength margs same) chooses'))
  mappedContracts fresh m (Solve {mfc} {args} {rest} {ns} spine split defines admits isDef evaluates held same chooses) =
    case mappedSpine m spine of
      (h' ** (more' ** (spine', mh, mmore))) => case metaImage mh of
        (scope' ** (headed, mscope, _)) =>
          case allMappedSplit args rest split (allMappedAppend mscope mmore) of
            (args' ** (rest' ** (split', margs, mrest))) =>
              case mappedChooses fresh (fresh defines isDef held) (mappedArguments margs ns same (sameLength margs same)) chooses of
                (v' ** (mv', chooses')) =>
                  (apply mfc v' rest' **
                    (mappedApply mv' mrest,
                     Solve (spineAt spine' headed) split' defines admits isDef evaluates held (sameLength margs same) chooses'))
  mappedContracts fresh m (Primitive spine defines admits isDef counted computes) =
    case mappedSpine m spine of
      (h' ** (args' ** (spine', mh, margs))) => case mappedComputes margs computes of
        (v' ** (mv', computes')) =>
          (v' ** (mv', Primitive (spineAt spine' (funcImage mh)) defines admits isDef (sameLength margs counted) computes'))
  mappedContracts fresh (MForce (MDelay _ ma)) ForceDelay = (_ ** (ma, ForceDelay))
  mappedContracts fresh (MAs _ mt) (RemoveAs removes) = (_ ** (mt, RemoveAs removes))
  mappedContracts fresh (MApp (MAs mn mt) ma) (FloatAs keeps) = (_ ** (MAs (MApp mn ma) (MApp mt ma), FloatAs keeps))
  mappedContracts {c} fresh (MApp (MBind mb msc) ma) (FloatBinder floats) =
    (_ ** (MBind mb (MApp msc (mappedWeaken c ma)), FloatBinder (mappedFloats mb floats)))
  mappedContracts fresh (MApp (MDelayed mt) ma) FloatDelayed = (_ ** (MDelayed (MApp mt ma), FloatDelayed))
  mappedContracts fresh (MApp (MDotted mt) ma) FloatDot = (_ ** (MDotted (MApp mt ma), FloatDot))
  mappedContracts fresh (MApp mf _) (DropApplied drops) = (_ ** (mf, DropApplied (mappedDrops mf drops)))
  mappedContracts fresh (MRef _) (TypeName root) = (_ ** (MType, TypeName root))
  mappedContracts fresh (MRef _) (ConstantTypeName named) = (_ ** (MPrim, ConstantTypeName named))

  0 mappedScrutinised : FreshIn ctx bs -> Mapped mv bs vals c t t' -> Scrutinised ev ctx t s ->
                        (s' : Term ys ** (Mapped mv bs vals c s s', Scrutinised ev ctx t' s'))
  mappedScrutinised fresh m (AsItIs shows) = case mappedShows m shows of
    (s' ** (ms, shows')) => (s' ** (ms, AsItIs shows'))
  mappedScrutinised fresh m (ImplementationUnfolded {ns} spine defines forTypes impl visible isDef evaluates held same chooses reduces shows) =
    case mappedSpine m spine of
      (h' ** (args' ** (spine', mh, margs))) =>
        case mappedChooses fresh (fresh defines isDef held) (mappedArguments margs ns same (sameLength margs same)) chooses of
          (u' ** (mu, chooses')) => case mappedReduces fresh mu reduces of
            (w' ** (mw, reduces')) => case mappedShows mw shows of
              (s' ** (ms, shows')) =>
                (s' ** (ms, ImplementationUnfolded (spineAt spine' (funcImage mh)) defines forTypes impl visible isDef
                                                   evaluates held (sameLength margs same) chooses' reduces' shows'))

  0 mappedChooses : {0 args : Scope} -> {0 env : SubstEnv args xs} -> {0 env' : SubstEnv args ys} ->
                    {0 tree : CaseTree args} ->
                    FreshIn ctx bs -> treeMentions bs tree = False -> EnvMapped mv bs vals c env env' ->
                    Chooses ev ctx env tree v -> (v' : Term ys ** (Mapped mv bs vals c v v', Chooses ev ctx env' tree v'))
  mappedChooses {args} {c} fresh fr envm (ToLeaf {rhs}) =
    (_ ** (mappedSubst c zero (mkSizeOf args) envm (mappedEmbed c (mkSizeOf args) rhs fr), ToLeaf))
  mappedChooses fresh fr envm (ByCase {p} scrutinised picks) =
    case mappedScrutinised fresh (envMappedAt envm (MkVar p)) scrutinised of
      (s' ** (ms, scrutinised')) => case mappedPicks fresh fr envm ms picks of
        (v' ** (mv', picks')) => (v' ** (mv', ByCase scrutinised' picks'))

  0 mappedPicks : FreshIn ctx bs -> altsMention bs alts = False -> EnvMapped mv bs vals c env env' ->
                  Mapped mv bs vals c s s' -> Picks ev ctx env s alts v ->
                  (v' : Term ys ** (Mapped mv bs vals c v v', Picks ev ctx env' s' alts v'))
  mappedPicks {bs} fresh fr envm ms (Takes {alt} matches) =
    case mappedMatches fresh (fst (orFalse (altMentions bs alt) fr)) envm ms matches of
      (v' ** (mv', matches')) => (v' ** (mv', Takes matches'))
  mappedPicks {bs} fresh fr envm ms (Skips {alt} misses picks) =
    case mappedPicks fresh (snd (orFalse (altMentions bs alt) fr)) envm ms picks of
      (v' ** (mv', picks')) => (v' ** (mv', Skips (mappedMisses ms misses) picks'))

  0 mappedMatches : FreshIn ctx bs -> altMentions bs alt = False -> EnvMapped mv bs vals c env env' ->
                    Mapped mv bs vals c s s' -> Matches ev ctx env s alt v ->
                    (v' : Term ys ** (Mapped mv bs vals c v v', Matches ev ctx env' s' alt v'))
  mappedMatches fresh sub envm ms (ByConstructor {cargs} spine entry same chooses) =
    case mappedSpine ms spine of
      (h' ** (fields' ** (spine', mh, mfields))) =>
        case mappedChooses fresh sub (mappedFields mfields cargs same (sameLength mfields same) envm) chooses of
          (v' ** (mv', chooses')) =>
            (v' ** (mv', ByConstructor (spineAt spine' (conImage mh)) entry (sameLength mfields same) chooses'))
  mappedMatches fresh sub envm ms (ByFamily {cargs} spine entry same chooses) =
    case mappedSpine ms spine of
      (h' ** (fields' ** (spine', mh, mfields))) =>
        case mappedChooses fresh sub (mappedFields mfields cargs same (sameLength mfields same) envm) chooses of
          (v' ** (mv', chooses')) =>
            (v' ** (mv', ByFamily (spineAt spine' (familyImage mh)) entry (sameLength mfields same) chooses'))
  mappedMatches fresh sub envm MPrim (ByPrimitiveType named chooses) = case mappedChooses fresh sub envm chooses of
    (v' ** (mv', chooses')) => (v' ** (mv', ByPrimitiveType named chooses'))
  mappedMatches fresh sub envm MType (ByUniverse root chooses) = case mappedChooses fresh sub envm chooses of
    (v' ** (mv', chooses')) => (v' ** (mv', ByUniverse root chooses'))
  mappedMatches fresh sub envm (MBind (MPi me mdom) mcod) (ByArrow root chooses) =
    case mappedChooses fresh sub (EnvEach mdom (EnvEach (MBind (MLam me mdom) mcod) envm)) chooses of
      (v' ** (mv', chooses')) => (v' ** (mv', ByArrow root chooses'))
  mappedMatches fresh sub envm (MDelay mty marg) (ByDelay chooses) =
    case mappedChooses fresh sub (EnvEach mty (EnvEach marg envm)) chooses of
      (v' ** (mv', chooses')) => (v' ** (mv', ByDelay chooses'))
  mappedMatches fresh sub envm MPrim (ByConstant equal chooses) = case mappedChooses fresh sub envm chooses of
    (v' ** (mv', chooses')) => (v' ** (mv', ByConstant equal chooses'))
  mappedMatches fresh sub envm ms (ByDefaultCase concrete chooses) = case mappedChooses fresh sub envm chooses of
    (v' ** (mv', chooses')) => (v' ** (mv', ByDefaultCase (mappedConcrete ms concrete) chooses'))

------------------------------------------------------------------------------
-- Reduction is closed under strengthening
------------------------------------------------------------------------------

mutual
  0 mentionsNone : (k : Naming) -> (t : Term vs) -> mentions k None t = False
  mentionsNone k (Local fc l i p) = Refl
  mentionsNone BoundOrUnknown (Ref fc Bound n) = Refl
  mentionsNone UnknownOnly (Ref fc Bound n) = Refl
  mentionsNone k (Ref fc Func n) = Refl
  mentionsNone k (Ref fc (DataCon tag arity) n) = Refl
  mentionsNone k (Ref fc (TyCon arity) n) = Refl
  mentionsNone k (Meta fc m i args) = mentionsNoneAll k args
  mentionsNone k (Bind fc x b sc) = rewrite mentionsNoneBinder k b in mentionsNone k sc
  mentionsNone k (App fc f a) = rewrite mentionsNone k f in mentionsNone k a
  mentionsNone k (As fc s n t) = rewrite mentionsNone k n in mentionsNone k t
  mentionsNone k (TDelayed fc r t) = mentionsNone k t
  mentionsNone k (TDelay fc r ty a) = rewrite mentionsNone k ty in mentionsNone k a
  mentionsNone k (TForce fc r t) = mentionsNone k t
  mentionsNone k (PrimVal fc c) = Refl
  mentionsNone k (Erased fc Placeholder) = Refl
  mentionsNone k (Erased fc Impossible) = Refl
  mentionsNone k (Erased fc (Dotted t)) = mentionsNone k t
  mentionsNone k (TType fc u) = Refl

  0 mentionsNoneAll : (k : Naming) -> (ts : List (Term vs)) -> mentionsIn k None ts = False
  mentionsNoneAll k [] = Refl
  mentionsNoneAll k (t :: ts) = rewrite mentionsNone k t in mentionsNoneAll k ts

  0 mentionsNoneBinder : (k : Naming) -> (b : Binder (Term vs)) -> mentionsInBinder k None b = False
  mentionsNoneBinder k (Lam fc c p ty) = rewrite mentionsNonePi k p in mentionsNone k ty
  mentionsNoneBinder k (Let fc c v ty) = rewrite mentionsNone k v in mentionsNone k ty
  mentionsNoneBinder k (Pi fc c p ty) = rewrite mentionsNonePi k p in mentionsNone k ty
  mentionsNoneBinder k (PVar fc c p ty) = rewrite mentionsNonePi k p in mentionsNone k ty
  mentionsNoneBinder k (PLet fc c v ty) = rewrite mentionsNone k v in mentionsNone k ty
  mentionsNoneBinder k (PVTy fc c ty) = mentionsNone k ty

  0 mentionsNonePi : (k : Naming) -> (p : PiInfo (Term vs)) -> mentionsInPi k None p = False
  mentionsNonePi k Implicit = Refl
  mentionsNonePi k Explicit = Refl
  mentionsNonePi k AutoImplicit = Refl
  mentionsNonePi k (DefImplicit t) = mentionsNone k t

mutual
  0 treeMentionsNone : (tree : CaseTree args) -> treeMentions None tree = False
  treeMentionsNone (Case idx p ty alts) = altsMentionNone alts
  treeMentionsNone (STerm i rhs) = mentionsNone BoundOrUnknown rhs
  treeMentionsNone (Unmatched msg) = Refl
  treeMentionsNone Impossible = Refl

  0 altsMentionNone : (alts : List (CaseAlt args)) -> altsMention None alts = False
  altsMentionNone [] = Refl
  altsMentionNone (alt :: alts) = rewrite altMentionsNone alt in altsMentionNone alts

  0 altMentionsNone : (alt : CaseAlt args) -> altMentions None alt = False
  altMentionsNone (ConCase n tag cargs sc) = treeMentionsNone sc
  altMentionsNone (DelayCase ty arg sc) = treeMentionsNone sc
  altMentionsNone (ConstCase c sc) = treeMentionsNone sc
  altMentionsNone (DefaultCase sc) = treeMentionsNone sc

-- No bounds replace no name, so every context is fresh for them.
0 freshNone : FreshIn ctx None
freshNone {tree} _ _ _ = treeMentionsNone tree

||| Reduction is closed under strengthening: a term read without a variable
||| it does not mention steps as the term does, to what the term steps to,
||| read without the variable.
export
0 reducesStrengthened : Strengthened o t t' -> Reduces ev ctx t u ->
                        (u' : Term ys ** (Strengthened o u u', Reduces ev ctx t' u'))
reducesStrengthened s steps = mappedReduces freshNone s steps

||| A term is read without a variable in one way.
export
0 strengthenedOnce : {0 u, u' : Term ys} -> Strengthened o t u -> Strengthened o t u' -> u = u'
strengthenedOnce s s' = mappedOnce s s'

------------------------------------------------------------------------------
-- Reduction is closed under putting values in for fresh names
------------------------------------------------------------------------------

-- Where a name is among the names a set of bounds replaces: at the first
-- that replaces it, or at none.
0 firstOrNone : (bs : Bounds ns) -> (n : Name) -> Either (w : Var ns ** FirstAt bs w n) (NoneAt bs n)
firstOrNone None n = Right NoneHere
firstOrNone (Add new old rest) n with (n == old) proof same
  _ | True = Left (MkVar First ** AtHere same)
  _ | False = case firstOrNone rest n of
    Left (MkVar v ** at) => Left (MkVar (Later v) ** AtLater same at)
    Right none => Right (NotThis same none)

-- A name a set of bounds does not replace is not one it replaces.
0 noneNotReplaced : NoneAt bs n -> replaces bs n = False
noneNotReplaced NoneHere = Refl
noneNotReplaced (NotThis differs none) = rewrite differs in noneNotReplaced none

-- A bound reference to the name a set of bounds replaces first at a
-- variable is the value for that variable, weakened under the binders.
0 putInFirst : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
               FirstAt bs w n -> putIn o sz bs vs (Ref fc Bound n) = weakenNs o (Var.index vs w)
putInFirst {w} o sz (Add new old rest) vs at = middleBack o sz vs w (mkLocalsMarker {vars} o (Add new old rest) w at)
putInFirst o sz None vs (AtHere _) impossible
putInFirst o sz None vs (AtLater _ _) impossible

-- A bound reference to a name no bound replaces stays as it was.
0 putInNone : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
              NoneAt bs n -> putIn o sz bs vs (Ref fc Bound n) = Ref fc Bound n
putInNone o sz None vs _ = Refl
putInNone o sz (Add new old rest) vs none = cong (substTerm o sz vs) (mkLocalsUnreplaced {vars} o (Add new old rest) none)

mutual
  -- No bounds map every term to itself.
  0 mappedItself : (t : Term xs) -> Mapped KeepsLocals None vals c t t
  mappedItself (Local fc l i p) = MLocal Refl
  mappedItself (Ref fc Bound n) = MRef NoneHere
  mappedItself (Ref fc Func n) = MRef ()
  mappedItself (Ref fc (DataCon tag arity) n) = MRef ()
  mappedItself (Ref fc (TyCon arity) n) = MRef ()
  mappedItself (Meta fc m k args) = MMeta NoneHere (mappedItselfAll args)
  mappedItself (Bind fc x b sc) = MBind (mappedItselfBinder b) (mappedItself sc)
  mappedItself (App fc f a) = MApp (mappedItself f) (mappedItself a)
  mappedItself (As fc s n t) = MAs (mappedItself n) (mappedItself t)
  mappedItself (TDelayed fc r t) = MDelayed (mappedItself t)
  mappedItself (TDelay fc r ty a) = MDelay (mappedItself ty) (mappedItself a)
  mappedItself (TForce fc r t) = MForce (mappedItself t)
  mappedItself (PrimVal fc k) = MPrim
  mappedItself (Erased fc Placeholder) = MPlaceholder
  mappedItself (Erased fc Impossible) = MImpossible
  mappedItself (Erased fc (Dotted t)) = MDotted (mappedItself t)
  mappedItself (TType fc u) = MType

  0 mappedItselfAll : (ts : List (Term xs)) -> AllMapped KeepsLocals None vals c ts ts
  mappedItselfAll [] = MNone
  mappedItselfAll (t :: ts) = MEach (mappedItself t) (mappedItselfAll ts)

  0 mappedItselfBinder : (b : Binder (Term xs)) -> BinderMapped KeepsLocals None vals c b b
  mappedItselfBinder (Lam fc r p ty) = MLam (mappedItselfPi p) (mappedItself ty)
  mappedItselfBinder (Let fc r v ty) = MLet (mappedItself v) (mappedItself ty)
  mappedItselfBinder (Pi fc r p ty) = MPi (mappedItselfPi p) (mappedItself ty)
  mappedItselfBinder (PVar fc r p ty) = MPVar (mappedItselfPi p) (mappedItself ty)
  mappedItselfBinder (PLet fc r v ty) = MPLet (mappedItself v) (mappedItself ty)
  mappedItselfBinder (PVTy fc r ty) = MPVTy (mappedItself ty)

  0 mappedItselfPi : (p : PiInfo (Term xs)) -> PiMapped KeepsLocals None vals c p p
  mappedItselfPi Implicit = MImplicit
  mappedItselfPi Explicit = MExplicit
  mappedItselfPi AutoImplicit = MAutoImplicit
  mappedItselfPi (DefImplicit t) = MDefault (mappedItself t)

mutual
  -- Values put in for the names of bounds that replace at least one, node
  -- by node: `putIn` is `mkLocals` then `substTerm`, both public, so at
  -- each node but a local and a bound reference it is that node rebuilt
  -- from its parts with the values put in.
  0 putInMappedAdd : (o : SizeOf outer) -> (sz : SizeOf (x :: xs)) -> (rest : Bounds xs) ->
                     (vs : SubstEnv (x :: xs) vars) -> (t : Term (outer ++ vars)) ->
                     mentions UnknownOnly (Add x old rest) t = False ->
                     Mapped KeepsLocals (Add x old rest) vs (size o) t (putIn o sz (Add x old rest) vs t)
  putInMappedAdd {x} {old} o sz rest vs (Local fc l i p) _ =
    mappedLocals KeepsLocals (size o) IsLocalAt (putInLocal o sz (Add x old rest) vs p) Refl
  putInMappedAdd {x} {old} o sz rest vs (Ref fc Bound n) _ = case firstOrNone (Add x old rest) n of
    Left (w ** at) =>
      rewrite putInFirst {fc} o sz (Add x old rest) vs at in MMarker at (shiftedWeaken o (Var.index vs w))
    Right none =>
      rewrite putInNone {fc} o sz (Add x old rest) vs none in MRef none
  putInMappedAdd o sz rest vs (Ref fc Func n) _ = MRef ()
  putInMappedAdd o sz rest vs (Ref fc (DataCon tag arity) n) _ = MRef ()
  putInMappedAdd o sz rest vs (Ref fc (TyCon arity) n) _ = MRef ()
  putInMappedAdd {x} {old} {vars} o sz rest vs (Meta fc m k args) none =
    rewrite mkLocalsUnknown {vars} {fc} {k} {args} o (Add x old rest)
                            (noneAt (Add x old rest) (fst (orFalse (replaces (Add x old rest) m) none))) in
    MMeta (noneAt (Add x old rest) (fst (orFalse (replaces (Add x old rest) m) none)))
          (putInMappedAddAll o sz rest vs args (snd (orFalse (replaces (Add x old rest) m) none)))
  putInMappedAdd {x} {old} o@(MkSizeOf _ _) sz rest vs (Bind fc y b sc) none =
    MBind (putInMappedAddBinder o sz rest vs b (fst (orFalse (mentionsInBinder UnknownOnly (Add x old rest) b) none)))
          (putInMappedAdd (suc o) sz rest vs sc (snd (orFalse (mentionsInBinder UnknownOnly (Add x old rest) b) none)))
  putInMappedAdd {x} {old} o sz rest vs (App fc f a) none =
    MApp (putInMappedAdd o sz rest vs f (fst (orFalse (mentions UnknownOnly (Add x old rest) f) none)))
         (putInMappedAdd o sz rest vs a (snd (orFalse (mentions UnknownOnly (Add x old rest) f) none)))
  putInMappedAdd {x} {old} o sz rest vs (As fc s n t) none =
    MAs (putInMappedAdd o sz rest vs n (fst (orFalse (mentions UnknownOnly (Add x old rest) n) none)))
        (putInMappedAdd o sz rest vs t (snd (orFalse (mentions UnknownOnly (Add x old rest) n) none)))
  putInMappedAdd o sz rest vs (TDelayed fc r t) none = MDelayed (putInMappedAdd o sz rest vs t none)
  putInMappedAdd {x} {old} o sz rest vs (TDelay fc r ty a) none =
    MDelay (putInMappedAdd o sz rest vs ty (fst (orFalse (mentions UnknownOnly (Add x old rest) ty) none)))
           (putInMappedAdd o sz rest vs a (snd (orFalse (mentions UnknownOnly (Add x old rest) ty) none)))
  putInMappedAdd o sz rest vs (TForce fc r t) none = MForce (putInMappedAdd o sz rest vs t none)
  putInMappedAdd o sz rest vs (PrimVal fc k) _ = MPrim
  putInMappedAdd o sz rest vs (Erased fc Placeholder) _ = MPlaceholder
  putInMappedAdd o sz rest vs (Erased fc Impossible) _ = MImpossible
  putInMappedAdd o sz rest vs (Erased fc (Dotted t)) none = MDotted (putInMappedAdd o sz rest vs t none)
  putInMappedAdd o sz rest vs (TType fc u) _ = MType

  0 putInMappedAddAll : (o : SizeOf outer) -> (sz : SizeOf (x :: xs)) -> (rest : Bounds xs) ->
                        (vs : SubstEnv (x :: xs) vars) -> (ts : List (Term (outer ++ vars))) ->
                        mentionsIn UnknownOnly (Add x old rest) ts = False ->
                        AllMapped KeepsLocals (Add x old rest) vs (size o) ts
                                  (substTerms o sz vs (mkLocalsTerms {vars} o (Add x old rest) ts))
  putInMappedAddAll o sz rest vs [] _ = MNone
  putInMappedAddAll {x} {old} o sz rest vs (t :: ts) none =
    MEach (putInMappedAdd o sz rest vs t (fst (orFalse (mentions UnknownOnly (Add x old rest) t) none)))
          (putInMappedAddAll o sz rest vs ts (snd (orFalse (mentions UnknownOnly (Add x old rest) t) none)))

  0 putInMappedAddBinder : (o : SizeOf outer) -> (sz : SizeOf (x :: xs)) -> (rest : Bounds xs) ->
                           (vs : SubstEnv (x :: xs) vars) -> (b : Binder (Term (outer ++ vars))) ->
                           mentionsInBinder UnknownOnly (Add x old rest) b = False ->
                           BinderMapped KeepsLocals (Add x old rest) vs (size o) b
                                        (substBinder o sz vs (mkLocalsBinder {vars} o (Add x old rest) b))
  putInMappedAddBinder {x} {old} o sz rest vs (Lam fc r p ty) none =
    MLam (putInMappedAddPi o sz rest vs p (fst (orFalse (mentionsInPi UnknownOnly (Add x old rest) p) none)))
         (putInMappedAdd o sz rest vs ty (snd (orFalse (mentionsInPi UnknownOnly (Add x old rest) p) none)))
  putInMappedAddBinder {x} {old} o sz rest vs (Let fc r v ty) none =
    MLet (putInMappedAdd o sz rest vs v (fst (orFalse (mentions UnknownOnly (Add x old rest) v) none)))
         (putInMappedAdd o sz rest vs ty (snd (orFalse (mentions UnknownOnly (Add x old rest) v) none)))
  putInMappedAddBinder {x} {old} o sz rest vs (Pi fc r p ty) none =
    MPi (putInMappedAddPi o sz rest vs p (fst (orFalse (mentionsInPi UnknownOnly (Add x old rest) p) none)))
        (putInMappedAdd o sz rest vs ty (snd (orFalse (mentionsInPi UnknownOnly (Add x old rest) p) none)))
  putInMappedAddBinder {x} {old} o sz rest vs (PVar fc r p ty) none =
    MPVar (putInMappedAddPi o sz rest vs p (fst (orFalse (mentionsInPi UnknownOnly (Add x old rest) p) none)))
          (putInMappedAdd o sz rest vs ty (snd (orFalse (mentionsInPi UnknownOnly (Add x old rest) p) none)))
  putInMappedAddBinder {x} {old} o sz rest vs (PLet fc r v ty) none =
    MPLet (putInMappedAdd o sz rest vs v (fst (orFalse (mentions UnknownOnly (Add x old rest) v) none)))
          (putInMappedAdd o sz rest vs ty (snd (orFalse (mentions UnknownOnly (Add x old rest) v) none)))
  putInMappedAddBinder o sz rest vs (PVTy fc r ty) none = MPVTy (putInMappedAdd o sz rest vs ty none)

  0 putInMappedAddPi : (o : SizeOf outer) -> (sz : SizeOf (x :: xs)) -> (rest : Bounds xs) ->
                       (vs : SubstEnv (x :: xs) vars) -> (p : PiInfo (Term (outer ++ vars))) ->
                       mentionsInPi UnknownOnly (Add x old rest) p = False ->
                       PiMapped KeepsLocals (Add x old rest) vs (size o) p
                                (substPi o sz vs (mkLocalsPi {vars} o (Add x old rest) p))
  putInMappedAddPi o sz rest vs Implicit _ = MImplicit
  putInMappedAddPi o sz rest vs Explicit _ = MExplicit
  putInMappedAddPi o sz rest vs AutoImplicit _ = MAutoImplicit
  putInMappedAddPi o sz rest vs (DefImplicit t) none = MDefault (putInMappedAdd o sz rest vs t none)

-- Values put in for the names a set of bounds replaces map a term that
-- names no unknown by them to the term with the values put in.
0 putInMapped : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                (t : Term (outer ++ vars)) -> mentions UnknownOnly bs t = False ->
                Mapped KeepsLocals bs vs (size o) t (putIn o sz bs vs t)
putInMapped o sz None [] t _ = rewrite substNothing o sz t in mappedItself t
putInMapped o sz (Add x old rest) vs t none = putInMappedAdd o sz rest vs t none

mutual
  -- A term a map maps names no unknown its bounds replace.
  0 mappedNoUnknown : Mapped mv bs vals c t t' -> mentions UnknownOnly bs t = False
  mappedNoUnknown (MLocal _) = Refl
  mappedNoUnknown (MMarker _ _) = Refl
  mappedNoUnknown (MRef {nt = Bound} _) = Refl
  mappedNoUnknown (MRef {nt = Func} _) = Refl
  mappedNoUnknown (MRef {nt = DataCon _ _} _) = Refl
  mappedNoUnknown (MRef {nt = TyCon _} _) = Refl
  mappedNoUnknown (MMeta none xs) = rewrite noneNotReplaced none in mappedNoUnknownAll xs
  mappedNoUnknown (MBind b sc) = rewrite binderNoUnknown b in mappedNoUnknown sc
  mappedNoUnknown (MApp f a) = rewrite mappedNoUnknown f in mappedNoUnknown a
  mappedNoUnknown (MAs n x) = rewrite mappedNoUnknown n in mappedNoUnknown x
  mappedNoUnknown (MDelayed x) = mappedNoUnknown x
  mappedNoUnknown (MDelay ty a) = rewrite mappedNoUnknown ty in mappedNoUnknown a
  mappedNoUnknown (MForce x) = mappedNoUnknown x
  mappedNoUnknown MPrim = Refl
  mappedNoUnknown MPlaceholder = Refl
  mappedNoUnknown MImpossible = Refl
  mappedNoUnknown (MDotted x) = mappedNoUnknown x
  mappedNoUnknown MType = Refl

  0 mappedNoUnknownAll : AllMapped mv bs vals c ts ts' -> mentionsIn UnknownOnly bs ts = False
  mappedNoUnknownAll MNone = Refl
  mappedNoUnknownAll (MEach x xs) = rewrite mappedNoUnknown x in mappedNoUnknownAll xs

  0 binderNoUnknown : BinderMapped mv bs vals c b b' -> mentionsInBinder UnknownOnly bs b = False
  binderNoUnknown (MLam p ty) = rewrite piNoUnknown p in mappedNoUnknown ty
  binderNoUnknown (MLet v ty) = rewrite mappedNoUnknown v in mappedNoUnknown ty
  binderNoUnknown (MPi p ty) = rewrite piNoUnknown p in mappedNoUnknown ty
  binderNoUnknown (MPVar p ty) = rewrite piNoUnknown p in mappedNoUnknown ty
  binderNoUnknown (MPLet v ty) = rewrite mappedNoUnknown v in mappedNoUnknown ty
  binderNoUnknown (MPVTy ty) = mappedNoUnknown ty

  0 piNoUnknown : PiMapped mv bs vals c p p' -> mentionsInPi UnknownOnly bs p = False
  piNoUnknown MImplicit = Refl
  piNoUnknown MExplicit = Refl
  piNoUnknown MAutoImplicit = Refl
  piNoUnknown (MDefault t) = mappedNoUnknown t

||| Reduction is closed under putting values in for the names a set of
||| bounds replaces, where the names are fresh for the context (`FreshIn`)
||| and the term names no unknown by them: the term and what it reduces to
||| are each mapped to themselves with the values put in (`putInMapped`),
||| reduction is closed under that map (`mappedReduces`), and a map gives
||| one image (`mappedOnce`).
export
0 substitutes : {ns : Scope} -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                FreshIn ctx bs -> mentions UnknownOnly bs t = False ->
                Reduces ev ctx t u ->
                Reduces ev ctx (substs (mkSizeOf ns) vs (refsToLocals bs t))
                               (substs (mkSizeOf ns) vs (refsToLocals bs u))
substitutes {t} {u} bs vs fresh none steps =
  rewrite putInAtTop (mkSizeOf ns) bs vs t in
  rewrite putInAtTop (mkSizeOf ns) bs vs u in
  case mappedReduces fresh (putInMapped zero (mkSizeOf ns) bs vs t none) steps of
    (u' ** (mapped, steps')) =>
      rewrite mappedOnce (putInMapped zero (mkSizeOf ns) bs vs u (mappedNoUnknown mapped)) mapped in steps'

||| Normalising commutes with putting closed values in for fresh names:
||| the normal form of a term with the values put in is the normal form of
||| its normal form with them put in. The steps to the term's normal form,
||| with the values put in, lead from the term with them put in to that
||| normal form with them put in, a reduct of the term with the values put
||| in, which so reduces on to its normal form (`reachesNormalForm`). With
||| that normal form's evidence that it is normal, the steps are a reduct
||| of the normal form with the values put in, which no normaliser runs to
||| give: `MkReduct s.value (normalisesThrough bs vs fresh none r s) s.normal`.
export
0 normalisesThrough : {ns : Scope} -> (bs : Bounds ns) -> (vs : SubstEnv ns []) ->
                      FreshIn ctx bs -> mentions UnknownOnly bs t = False ->
                      (r : Reduct form ctx t) ->
                      (s : Reduct form ctx (substs (mkSizeOf ns) vs (refsToLocals bs t))) ->
                      Reduces (evaluationOf form) ctx
                              (substs (mkSizeOf ns) vs (refsToLocals bs r.value)) s.value
normalisesThrough bs vs fresh none r s = reachesNormalForm s (substitutes bs vs fresh none r.steps)

------------------------------------------------------------------------------
-- The frontend's probes are fresh
------------------------------------------------------------------------------

||| A name of the frontend's probes: one of their identifiers
||| (`Core.Name.Known.isProbe`) as a machine name or a user's, or a name
||| nested in one.
public export
data ProbeNamed : Name -> Type where
  NamedMachine : (0 _ : isProbe k = True) -> ProbeNamed (MN (known k) i)
  NamedUser : (0 _ : isProbe k = True) -> ProbeNamed (UN (Basic (known k)))
  NamedNested : ProbeNamed n -> ProbeNamed (Nested p n)

||| Bounds that replace only names of the frontend's probes.
public export
data AllProbeNamed : Bounds ns -> Type where
  NoneNamed : AllProbeNamed None
  EachNamed : ProbeNamed old -> AllProbeNamed bs -> AllProbeNamed (Add new old bs)

||| The frontend's probes are fresh for every frozen context: no definition
||| it holds names one, as a bound reference or an unknown, nor any name
||| Idris's equality of names takes for one. A probe's identifier holds a
||| dash, so no source spells it; the elaborator names nothing with one, and
||| a TTC holds only what the elaborator made; and two names are equal
||| only where their identifiers are, which the table of identifiers makes
||| one identifier. Those are facts of the `Core` actions that build the
||| context, as `oneEntryPerName` is, and no type of the context states
||| what names its terms hold: stating it would take reading every term of
||| every definition when the context is frozen, a cost for a fact the
||| context's making already keeps. So it is trusted.
export
0 probesFresh : AllProbeNamed bs -> FreshIn ctx bs
probesFresh _ = trusted

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
-- and no definition records a resolved name as its full name. These are
-- invariants the `Core` actions that build the context keep, over its
-- mutable table and its map of names, and no definition states them, so
-- they are trusted.
0 oneEntryPerName : {0 ctx : Frozen} -> {0 i, j : Int} ->
                    IntMap.lookup i (entriesOf ctx) = Just d -> IntMap.lookup j (entriesOf ctx) = Just d' ->
                    fullname d = fullname d' -> i = j
oneEntryPerName _ _ _ = trusted

0 fullNameUnresolved : {0 ctx : Frozen} -> {0 i : Int} ->
                       IntMap.lookup i (entriesOf ctx) = Just d -> Not (fullname d = Resolved k)
fullNameUnresolved _ _ = trusted

0 resolvedInjective : Resolved i = Resolved j -> i = j
resolvedInjective Refl = Refl

||| A resolved name made full is the full name of the definition at its
||| entry: `fullNameIn` reads that definition's.
export
0 entryFullName : {0 ctx : Frozen} -> {0 i : Int} ->
                  IntMap.lookup i (entriesOf ctx) = Just d -> fullNameIn ctx (Resolved i) = fullname d
entryFullName held = cong (maybe (Resolved i) fullname) held

||| The entry a name resolves to, made full, is the full name of the
||| definition the context gives the name, whatever spelling the name has:
||| the definition is the one at that entry.
export
0 definedFullName : Defines ctx n d -> (i : Int ** (Resolves ctx n i, fullNameIn ctx (Resolved i) = fullname d))
definedFullName (AtEntry {i} r held) = (i ** (r, entryFullName held))

||| A resolved name the context defines, made full, is the full name of its
||| definition: it resolves to its own entry, where the definition is.
export
0 resolvedDefinedFullName : Defines ctx (Resolved j) d -> fullNameIn ctx (Resolved j) = fullname d
resolvedDefinedFullName (AtEntry r held) = entryFullName (atEntry resolvedItself r held)

-- Two resolved names whose full names agree, read through what their
-- entries hold: two definitions, one, or none.
0 sameByFullName : {0 ctx : Frozen} -> {0 i, j : Int} -> (m, m' : Maybe GlobalDef) ->
                   IntMap.lookup i (entriesOf ctx) = m -> IntMap.lookup j (entriesOf ctx) = m' ->
                   maybe (Resolved i) Context.Context.fullname m = maybe (Resolved j) Context.Context.fullname m' -> i = j
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
  , checkTerminating
  , buildMain
  , processPackageOpts
  , emitError
  })
