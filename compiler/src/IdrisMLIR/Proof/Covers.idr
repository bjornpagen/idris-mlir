-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The parts the reading lemma (`Frontend.Growth.Template.ReadingCovers`)
||| is built from, each over the readers' relation (`ReadAs`) and the host's
||| (`Idris.Host.Reduces`):
|||
||| - at a node of the site's term an inert head heads, what an instance
|||   reads: the head over what each argument, the instance's values put
|||   in, reaches as a normal form, contracted with no redex left, and read
|||   (`atConstructor`, `familyRead`, `boundRead`), or a closed run's leaf;
||| - a match on a marker binding each field to a marker of its own, the
|||   part at the field's path, one match deeper (`pathStep`): the
|||   instance's value for that marker is the field, which the markers then
|||   hold too (`fieldMarkerHolds`), since any reading of the field is a
|||   child of a reading of the constructor applied (`readsAny`);
||| - a builtin read beside its call: the constant the host computes at an
|||   instance measures within one computation's growth of what its
|||   arguments measure (`computedMeasured`), the premise of
|||   `Proof.Bound.AtComputed`;
||| - the graph's rewrites of a site's template: what an instance writes
|||   under the reading, it writes under the template the graph keeps
|||   (`asGivenWrites`, `closedWrites`, `landedWrites`), from what the
|||   graph's builder establishes of the landings (`LandingsWrite`), a
|||   family read as computing being reached nowhere an instance writes in
|||   a feasible graph (`computingUnreached`);
||| - two readings of one term as an instance's are one reading but for an
|||   argument's number and a run read as its leaf (`readsAlike`), so a
|||   request's argument, which a site wrote, holds the requested
|||   instance's markers (`requestHolds`);
||| - contraction is maximal: an eta-normal term contracts to itself
|||   (`etaNormalFixed`);
||| - the reading lemma's induction, stated per node (`NodeCovers`), and
|||   proved at the root of a kind read off the host's normal form, whose
|||   instance form holds no redex (`coversAtRoot`), at a marker
|||   (`markerWrites`), at a constant, a universe and an erased part, which
|||   the host's steps only move (`atConstant`, `atUniverse`, `atErased`),
|||   at a closed run the site reads as its leaf (`runCovers`), at a data
|||   constructor, read node by node or as a closed run's leaf by the
|||   instance (`dataCovers`), and at a function the context defines as
|||   nothing, read as a part over its arguments by site and instance alike
|||   (`undefinedCovers`); the host's reduction of a lone lambda or
|||   function type keeps the binder (`lambdaReduces`, `piReduces`);
||| - at a head the host rewrites by its shape, where the site's form takes
|||   no such step, as a form read off the host's normal form takes none
|||   anywhere (`Proof.Reading.readNoShapeStep`): a type constructor of no
|||   arguments whose name names no type, which the host's steps only move,
|||   at whatever location (`unnamedTypeReduces`, `atNamedType`); a head
|||   that drops what it is applied to, met alone (`dropsAlone`); and no
|||   `let` where the evaluation runs everything (`noLetWhereRun`).
|||
||| The induction is not yet whole, so the run-time re-check stays. What it
||| lacks, each a fact no proof here states yet:
||| - from the site's term to its form: `coversAtRoot` asks `NodeCovers` of
|||   the site's term, whose instance the values are put into, while the
|||   site's reading is of its form, the host's normal form of the term
|||   contracted. Relating them needs the instance's normal form reached
|||   from the site's normal form with the values put in (the host's
|||   `substitutes` carries the site's steps through putting the values in,
|||   and `reachesNormalForm` the rest), and then contraction carried
|||   through putting values in, which no relation here states; and the
|||   site's normality (`readNoShapeStep`) as a premise of `NodeCovers` at
|||   each node, which the lemmas above take;
||| - under a binder: `NodeCovers` states closed terms only; a lambda's or
|||   a function type's body is read in a scope the instance's values are
|||   put in under (`putIn` at an outer scope) with its variable read as an
|||   argument of the value, so the induction needs that statement, and,
|||   where the instance contracts a lambda the site keeps, a reading of
|||   `g x` from a reading of `g` (`DropsLast`);
||| - a call the site reads beside its unfolding (`SBeside`, `Reducing`,
|||   `Unfolds`): the instance's evaluation of the call with the values put
|||   in either takes no `Unfold` step, leaving the call as written, or
|||   takes the one whose `Chooses` walks the same alternatives the trace
|||   took, which needs the frontend's `scrutineeOf` related to the host's
|||   `Scrutinised`, `Picks` and `Misses` through `putIn` (each alternative
|||   the trace passes by `TakenBy`'s `PassesThis`, `TagShared` or
|||   `LiteralPasses` a `Misses`, each it takes a `Matches`), and the
|||   instance's normal form of the leaf related to the site's reading of
|||   it (`Idris.Host.reachesNormalForm` with putting values in commuting
|||   with the normaliser's steps);
||| - a name the context gives no address (`SNoDefinition`): the induction
|||   there is proved from the context defining the name as nothing
|||   (`undefinedCovers`), which follows from every defined name having an
|||   address (`unaddressedUndefined`, over `PlacedWhereDefined`). That
|||   fact is the host's and no module states it: `Idris.Host` stating that
|||   a name it defines resolves to an entry that is not negative (its
|||   frozen entries are read from entry 0 up, but `IntMap` states nothing
|||   of a lookup after an insert, so the host carries the fact where it
|||   reads them), and `Walk.placementIn` and
|||   `Definitions.definitionAddress` giving an address to a name resolved
|||   to such an entry; a site's skeleton, which cuts the part to a leaf,
|||   is not covered by it;
||| - a dictionary and a shape a constructor heads, read as written: their
|||   form keeps the host's steps (`Proof.Reading.ReadOff`) but not their
|||   normality, and where the term has no unknown it is the term itself
|||   (`Template.solvedIn`), which the holes evaluation may still step (a
|||   definition that always reduces, a lambda applied), so neither
|||   `reachesNormalForm`, which needs a `Reduct`, nor one normal form per
|||   term relates the instance's form to the site's with the values put
|||   in; and a dictionary over runtime values is the implementation the
|||   frontend's own reduction finds (`FromImplementation`), which no
|||   relation of the host's states.
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Covers

import Core.Context
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

import IdrisMLIR.Frontend.Growth.Graph
import IdrisMLIR.Frontend.Growth.Heads
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Contraction
import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Literals
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Derivation
import IdrisMLIR.Proof.Describes
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Inversion
import IdrisMLIR.Proof.Markers
import IdrisMLIR.Proof.Primitives
import IdrisMLIR.Proof.Reading
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Control.Relation
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.Vect

%default total

-- A reading's evidence is its `describes`; the graph's proof that it
-- describes its model is never read here.
%hide IdrisMLIR.Proof.Describes.describes

0 justSame : Just x = Just y -> x = y
justSame Refl = Refl

0 justNotNothing : Just x = Nothing -> Void
justNotNothing Refl impossible

0 nothingNotJust : Nothing = Just x -> Void
nothingNotJust Refl impossible

------------------------------------------------------------------------------
-- A spine, read
------------------------------------------------------------------------------

||| A spine read as its head applied to every argument: an application is
||| read as its function with one more argument (`SApp`).
export
0 spineRead : Spine t h args -> SpineAs m env t as r -> SpineAs m env h (args ++ as) r
spineRead Host.Head s = s
spineRead {as} (Host.Applied {args = pre} {a} sp) (SApp s) =
  rewrite sym (appendAssociative pre [a] as) in spineRead sp s

||| A head read applied to a spine's arguments is the spine read.
export
0 spineReadBack : Spine t h args -> SpineAs m env h (args ++ as) r -> SpineAs m env t as r
spineReadBack Host.Head s = s
spineReadBack {as} (Host.Applied {args = pre} {a} sp) s =
  SApp (spineReadBack sp (replace {p = \zs => SpineAs m env h zs r} (sym (appendAssociative pre [a] as)) s))

------------------------------------------------------------------------------
-- An instance's reading at an inert head
------------------------------------------------------------------------------

-- A closed run is a data constructor's spine: no type constructor, no
-- bound name and no constant heads one.
0 runNotFamily : Run u k -> Spine u (Ref fc (TyCon arity) n) args -> Void
runNotFamily Literals.RunZero Host.Head impossible
runNotFamily Literals.RunZero (Host.Applied _) impossible
runNotFamily (RunSucc _) Host.Head impossible
runNotFamily (RunSucc _) (Host.Applied Host.Head) impossible
runNotFamily (RunSucc _) (Host.Applied (Host.Applied _)) impossible

0 runNotBound : Run u k -> Spine u (Ref fc Bound n) args -> Void
runNotBound Literals.RunZero Host.Head impossible
runNotBound Literals.RunZero (Host.Applied _) impossible
runNotBound (RunSucc _) Host.Head impossible
runNotBound (RunSucc _) (Host.Applied Host.Head) impossible
runNotBound (RunSucc _) (Host.Applied (Host.Applied _)) impossible

0 runNotConstant : Run (PrimVal fc c) k -> Void
runNotConstant Literals.RunZero impossible
runNotConstant (RunSucc _) impossible

||| An instance's reading of a term a data constructor heads: a closed
||| run's leaf, or the constructor, by the address the context gives it,
||| over its arguments' readings.
public export
data ConstructorRead : Frozen -> Values Substitute vs -> Name -> TT vs -> List (TT vs) -> Template -> Type where
  ReadAsRun : Run u k -> ConstructorRead ctx env n u args (Leaf (S k))
  ReadAsConstructor : (0 _ : AddressedAs (InstanceMode ctx) n a) -> AllReadAs (InstanceMode ctx) env args ts ->
                      ConstructorRead ctx env n u args (Head a ts)

-- A constructor applied, read by its head.
0 dataSpine : SpineAs (InstanceMode ctx) env (Ref fc (DataCon tag arity) n) as r ->
              (a : Maybe Address ** ts : List Template **
                (r = Head a ts, AddressedAs (InstanceMode ctx) n a, AllReadAs (InstanceMode ctx) env as ts))
dataSpine (SData at rs) = (_ ** _ ** (Refl, at, rs))

export
0 constructorRead : Spine u (Ref fc (DataCon tag arity) n) args -> ReadAs (InstanceMode ctx) env u r ->
                    ConstructorRead ctx env n u args r
constructorRead s (ARun run) = ReadAsRun run
constructorRead {args} s (ASpine sp) = case dataSpine (spineRead s sp) of
  (a ** ts ** (Refl, at, rs)) =>
    ReadAsConstructor at (replace {p = \zs => AllReadAs (InstanceMode ctx) env zs ts} (appendNilRightNeutral args) rs)

-- A type constructor applied, read by its head.
0 familySpine : SpineAs (InstanceMode ctx) env (Ref fc (TyCon arity) n) as r ->
                (a : Maybe Address ** ts : List Template **
                  (r = Head a ts, AddressedAs (InstanceMode ctx) n a, AllReadAs (InstanceMode ctx) env as ts))
familySpine (STypeCon at rs) = (_ ** _ ** (Refl, at, rs))

||| An instance's reading of a term a type constructor heads: the type
||| constructor, by its address, over its arguments' readings.
export
0 familyRead : Spine u (Ref fc (TyCon arity) n) args -> ReadAs (InstanceMode ctx) env u r ->
               (a : Maybe Address ** ts : List Template **
                 (r = Head a ts, AddressedAs (InstanceMode ctx) n a, AllReadAs (InstanceMode ctx) env args ts))
familyRead s (ARun run) = void (runNotFamily run s)
familyRead {args} s (ASpine sp) = case familySpine (spineRead s sp) of
  (a ** ts ** (same, at, rs)) =>
    (a ** ts ** (same, at, replace {p = \zs => AllReadAs (InstanceMode ctx) env zs ts} (appendNilRightNeutral args) rs))

||| What an instance reads a bound name as, over its arguments' readings: a
||| hole marker its token, an argument of a family's value its own, any
||| other name one node.
public export
data BoundRead : Name -> List Template -> Template -> Type where
  HoleRead : (0 _ : Readings.markerOf n = Just i) -> BoundRead n ts (partOf EveryNode (Token (S i)) ts)
  FormalRead : (0 _ : probeOf n = Just (ProbeFormal j k)) -> BoundRead n ts (partOf EveryNode (Formal j k) ts)
  PartRead : (0 _ : Readings.markerOf n = Nothing) -> (0 _ : NotFormal n) -> BoundRead n ts (partOf EveryNode (Leaf 1) ts)

0 boundSpine : SpineAs (InstanceMode ctx) env (Ref fc Bound n) as r ->
               (ts : List Template ** (BoundRead n ts r, AllReadAs (InstanceMode ctx) env as ts))
boundSpine (SHole hole rs) = (_ ** (HoleRead hole, rs))
boundSpine (SFormal _ formal rs) = (_ ** (FormalRead formal, rs))
boundSpine (SPart none plain rs) = (_ ** (PartRead none plain, rs))

||| An instance's reading of a term a bound name heads.
export
0 boundRead : Spine u (Ref fc Bound n) args -> ReadAs (InstanceMode ctx) env u r ->
              (ts : List Template ** (BoundRead n ts r, AllReadAs (InstanceMode ctx) env args ts))
boundRead s (ARun run) = void (runNotBound run s)
boundRead {args} s (ASpine sp) = case boundSpine (spineRead s sp) of
  (ts ** (named, rs)) => (ts ** (named, replace {p = \zs => AllReadAs (InstanceMode ctx) env zs ts} (appendNilRightNeutral args) rs))

||| What an instance reads at each argument of a node: the normal form the
||| argument, values put in, reduces to, contracted with no redex left, and
||| read.
public export
data ArgumentsRead : Evaluation -> Frozen -> List ClosedTerm -> List Template -> Type where
  NoneRead : ArgumentsRead ev ctx [] []
  EachRead : Reduces ev ctx a w -> Irreducible ev ctx w -> EtaContracts w u -> EtaNormal EveryRedex u ->
             ReadAs (InstanceMode ctx) [] u t -> ArgumentsRead ev ctx as ts -> ArgumentsRead ev ctx (a :: as) (t :: ts)

0 argumentsRead : {0 ev : Evaluation} -> AllReduce ev ctx as ws -> All (Irreducible ev ctx) ws -> AllContract ws us ->
                  All (EtaNormal EveryRedex) us -> AllReadAs (InstanceMode ctx) [] us ts -> ArgumentsRead ev ctx as ts
argumentsRead NoneLeft [] NoneContracted [] [] = NoneRead
argumentsRead (Each r rs) (n :: ns) (EachContracted c cs) (e :: es) (x :: xs) = EachRead r n c e x (argumentsRead rs ns cs es xs)

-- One more property after properties of each, at the end.
0 allAtEnd : {0 p : a -> Type} -> All p xs -> p x -> All p (xs ++ [x])
allAtEnd [] px = [px]
allAtEnd (q :: qs) px = q :: allAtEnd qs px

||| Every argument of a term with no redex left is one with none: a spine's
||| arguments are parts of its applications (`NormalApp`).
export
0 spineNormal : Spine v h args -> EtaNormal how v -> All (EtaNormal how) args
spineNormal Host.Head _ = []
spineNormal (Host.Applied s) (NormalApp nf na) = allAtEnd (spineNormal s nf) na

||| What an instance reads where the site's term has a data constructor
||| applied: a closed run's leaf, or the constructor, by the address the
||| context gives it, over what each argument reaches.
public export
data AtConstructor : Evaluation -> Frozen -> Name -> List ClosedTerm -> Template -> Type where
  RunAtConstructor : Run v k -> AtConstructor ev ctx n args (Leaf (S k))
  HeadAtConstructor : (0 _ : AddressedAs (InstanceMode ctx) n a) -> ArgumentsRead ev ctx args ts ->
                      AtConstructor ev ctx n args (Head a ts)

||| The inversion of an instance's reading at a data constructor: whatever
||| the instance's values, its term reduces under the constructor
||| (`Proof.Inversion.inertPutIn`), each argument of its normal form is
||| normal (`Proof.Inversion.argumentsIrreducible`), contraction keeps the
||| constructor (`Proof.Inversion.refContracts`), and the reading reads the
||| constructor over the arguments' readings, or a closed run's leaf.
export
0 atConstructor : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns []) ->
                  Spine u (Ref fc (DataCon tag arity) n) args ->
                  Reduces ev ctx (putIn SizeOf.zero sz bs vs u) w -> Irreducible ev ctx w -> EtaContracts w v ->
                  EtaNormal EveryRedex v -> ReadAs (InstanceMode ctx) [] v r ->
                  AtConstructor ev ctx n (map (putIn SizeOf.zero sz bs vs) args) r
atConstructor sz bs vs s steps normal contracted maximal read =
  case inertPutIn SizeOf.zero sz bs vs InertData KeptData s steps of
    ReducedUnder sw rs => case refContracts sw contracted of
      ContractedUnder sv cs => case constructorRead sv read of
        ReadAsRun run => RunAtConstructor run
        ReadAsConstructor at reads =>
          HeadAtConstructor at (argumentsRead rs (argumentsIrreducible sw normal) cs (spineNormal sv maximal) reads)

||| The same at a type constructor of arguments: the type constructor over
||| what each argument reaches.
export
0 atFamily : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns []) ->
             Spine u (Ref fc (TyCon (S arity)) n) args ->
             Reduces ev ctx (putIn SizeOf.zero sz bs vs u) w -> Irreducible ev ctx w -> EtaContracts w v ->
             EtaNormal EveryRedex v -> ReadAs (InstanceMode ctx) [] v r ->
             (a : Maybe Address ** ts : List Template **
               (r = Head a ts, AddressedAs (InstanceMode ctx) n a, ArgumentsRead ev ctx (map (putIn SizeOf.zero sz bs vs) args) ts))
atFamily sz bs vs s steps normal contracted maximal read =
  case inertPutIn SizeOf.zero sz bs vs InertFamily KeptFamily s steps of
    ReducedUnder sw rs => case refContracts sw contracted of
      ContractedUnder sv cs => case familyRead sv read of
        (a ** ts ** (same, at, reads)) =>
          (a ** ts ** (same, at, argumentsRead rs (argumentsIrreducible sw normal) cs (spineNormal sv maximal) reads))

||| The same at a bound name no value is put in for: the name over what
||| each argument reaches.
export
0 atBound : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns []) ->
            (0 _ : replaces bs n = False) -> Spine u (Ref fc Bound n) args ->
            Reduces ev ctx (putIn SizeOf.zero sz bs vs u) w -> Irreducible ev ctx w -> EtaContracts w v ->
            EtaNormal EveryRedex v -> ReadAs (InstanceMode ctx) [] v r ->
            (ts : List Template ** (BoundRead n ts r, ArgumentsRead ev ctx (map (putIn SizeOf.zero sz bs vs) args) ts))
atBound sz bs vs none s steps normal contracted maximal read =
  case inertPutIn SizeOf.zero sz bs vs InertBound (KeptBound none) s steps of
    ReducedUnder sw rs => case refContracts sw contracted of
      ContractedUnder sv cs => case boundRead sv read of
        (ts ** (named, reads)) => (ts ** (named, argumentsRead rs (argumentsIrreducible sw normal) cs (spineNormal sv maximal) reads))

------------------------------------------------------------------------------
-- Every term has an instance's reading
------------------------------------------------------------------------------

mutual
  ||| Every term has a reading as an instance's term, as it has a key: each
  ||| node of it is read by its head, a lambda's variable as an argument
  ||| of the value (of any arity; 0 here).
  export
  0 readsAny : (ctx : Frozen) -> (env : Values Substitute vs) -> (t : TT vs) -> (r : Template ** ReadAs (InstanceMode ctx) env t r)
  readsAny ctx env t = case spineReadsAny ctx env t [] [] of
    (r ** s) => (r ** ASpine s)

  export
  0 readsAnyAll : (ctx : Frozen) -> (env : Values Substitute vs) -> (ts : List (TT vs)) ->
                  (rs : List Template ** AllReadAs (InstanceMode ctx) env ts rs)
  readsAnyAll ctx env [] = ([] ** [])
  readsAnyAll ctx env (t :: ts) = case readsAny ctx env t of
    (r ** x) => case readsAnyAll ctx env ts of
      (rs ** xs) => (r :: rs ** x :: xs)

  0 passingReadsAny : (ctx : Frozen) -> (env : Values Substitute vs) -> (info : PiInfo (TT vs)) ->
                      (ps : List Template ** PassingAs (InstanceMode ctx) env info ps)
  passingReadsAny ctx env Implicit = ([] ** PImplicit)
  passingReadsAny ctx env Explicit = ([] ** PExplicit)
  passingReadsAny ctx env AutoImplicit = ([] ** PAuto)
  passingReadsAny ctx env (DefImplicit d) = case readsAny ctx env d of
    (r ** x) => ([r] ** PDefault x)

  0 spineReadsAny : (ctx : Frozen) -> (env : Values Substitute vs) -> (t : TT vs) -> (as : List (TT vs)) ->
                    AllReadAs (InstanceMode ctx) env as ts -> (r : Template ** SpineAs (InstanceMode ctx) env t as r)
  spineReadsAny ctx env (App fc f a) as rs = case readsAny ctx env a of
    (r ** x) => case spineReadsAny ctx env f (a :: as) (x :: rs) of
      (u ** s) => (u ** SApp s)
  spineReadsAny ctx env (Erased fc (Dotted u)) as rs = case readsAny ctx env u of
    (r ** x) => (_ ** SDot x rs)
  spineReadsAny ctx env (Erased fc Placeholder) as rs = (_ ** SPlaceholder rs)
  spineReadsAny ctx env (Erased fc Impossible) as rs = (_ ** SImpossible rs)
  spineReadsAny ctx env (Local fc l idx p) as rs = (_ ** SLocal rs)
  spineReadsAny ctx env (Meta fc x i margs) as rs = case readsAnyAll ctx env margs of
    (ms ** xs) => (_ ** SMeta xs rs)
  spineReadsAny ctx env (TType fc u) as rs = (_ ** SUniverse rs)
  spineReadsAny ctx env (PrimVal fc c) as rs = (_ ** SConstant rs)
  spineReadsAny {vs} ctx env (Bind fc x (Lam lfc rig info ty) sc) as rs = case passingReadsAny ctx env info of
    (ps ** xp) => case readsAny ctx env ty of
      (t ** xt) => case readsAny ctx (FormalArgument (length vs) 0 :: env) sc of
        (s ** xs) => (_ ** SLambda xp xt xs rs)
  spineReadsAny ctx env (Bind fc x (Let lfc rig v ty) sc) as rs = case readsAny ctx env v of
    (tv ** xv) => case readsAny ctx env ty of
      (t ** xt) => case readsAny ctx (Placeholding :: env) sc of
        (s ** xs) => (_ ** SBinder (BLet xv xt) xs rs)
  spineReadsAny ctx env (Bind fc x (Pi lfc rig info ty) sc) as rs = case passingReadsAny ctx env info of
    (ps ** xp) => case readsAny ctx env ty of
      (t ** xt) => case readsAny ctx (Placeholding :: env) sc of
        (s ** xs) => (_ ** SBinder (BPi xp xt) xs rs)
  spineReadsAny ctx env (Bind fc x (PVar lfc rig info ty) sc) as rs = case passingReadsAny ctx env info of
    (ps ** xp) => case readsAny ctx env ty of
      (t ** xt) => case readsAny ctx (Placeholding :: env) sc of
        (s ** xs) => (_ ** SBinder (BPVar xp xt) xs rs)
  spineReadsAny ctx env (Bind fc x (PLet lfc rig v ty) sc) as rs = case readsAny ctx env v of
    (tv ** xv) => case readsAny ctx env ty of
      (t ** xt) => case readsAny ctx (Placeholding :: env) sc of
        (s ** xs) => (_ ** SBinder (BPLet xv xt) xs rs)
  spineReadsAny ctx env (Bind fc x (PVTy lfc rig ty) sc) as rs = case readsAny ctx env ty of
    (t ** xt) => case readsAny ctx (Placeholding :: env) sc of
      (s ** xs) => (_ ** SBinder (BPVTy xt) xs rs)
  spineReadsAny ctx env (TDelayed fc r u) as rs = case readsAny ctx env u of
    (t ** x) => (_ ** SDelayed x rs)
  spineReadsAny ctx env (TDelay fc r ty a) as rs = case readsAny ctx env ty of
    (t ** xt) => case readsAny ctx env a of
      (v ** xa) => (_ ** SDelay xt xa rs)
  spineReadsAny ctx env (TForce fc r u) as rs = case readsAny ctx env u of
    (t ** x) => (_ ** SForce x rs)
  spineReadsAny ctx env (As fc side a p) as rs = case readsAny ctx env a of
    (t ** xa) => case readsAny ctx env p of
      (v ** xp) => (_ ** SAs xa xp rs)
  spineReadsAny ctx env (Ref fc Bound n) as rs = case holeView n of
    IsHole i hole => (_ ** SHole hole rs)
    NotHole none => case formalView n of
      IsFormal j k formal => (_ ** SFormal none formal rs)
      NotFormalName plain => (_ ** SPart none plain rs)
  spineReadsAny ctx env (Ref fc (DataCon tag arity) n) as rs = (_ ** SData Refl rs)
  spineReadsAny ctx env (Ref fc (TyCon arity) n) as rs = (_ ** STypeCon Refl rs)
  spineReadsAny ctx env (Ref fc Func n) as rs with (definitionAddress (gamma (defsOf ctx)) n) proof found
    _ | Just a = (_ ** SKept found rs)
    _ | Nothing = (_ ** SNoDefinition found rs)

------------------------------------------------------------------------------
-- One marker per field
------------------------------------------------------------------------------

-- The readings of some terms with the reading at one place another reading
-- of the term there.
0 replaceRead : AllReadAs m env ts rs -> Elem t ts -> ReadAs m env t u -> (rs' : List Template ** (AllReadAs m env ts rs', Elem u rs'))
replaceRead {u} ((::) {ts = rest} _ xs) Here x = (u :: rest ** (x :: xs, Here))
replaceRead ((::) {t = r} y xs) (There el) x = case replaceRead xs el x of
  (rs' ** (xs', el')) => (r :: rs' ** (y :: xs', There el'))

-- Where the markers held the instance's values, they hold with a value one
-- match deeper added, put in for a marker read so: the value is a field of
-- the data constructor the instance's value for x is applied, and any
-- reading of the field is a child of a reading of the constructor applied.
0 deeperMarkerHolds : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {ctx : Frozen} ->
                      {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
                      MarkersHold m s ctx stands bs vs -> (x : Var ns) ->
                      walkMarker stands (replacedAt bs x) = Just (Template.Var i d) ->
                      Spine (Var.index vs x) (Ref fc (DataCon tag arity) cn) fields -> Elem f fields ->
                      walkMarker stands y = Just (Template.Var i (S d)) ->
                      MarkersHold m s ctx stands (Add new y bs) (f :: vs)
deeperMarkerHolds held x marked spine el named (MkVar First) i' d' named' u read =
  case justSame (trans (sym named') named) of
    Refl => case readsAnyAll ctx [] fields of
      (rs ** xs) => case replaceRead xs el read of
        (rs' ** (xs', at)) =>
          let whole = ASpine (spineReadBack spine
                        (SData {a = definitionAddress (gamma (defsOf ctx)) cn} Refl
                           (replace {p = \zs => AllReadAs (InstanceMode ctx) [] zs rs'} (sym (appendNilRightNeutral fields)) xs')))
          in case held x i d marked _ whole of
               (p ** v ** u' ** (wrote, inV, sub, again)) => case fieldHolds sub again at of
                 (u'' ** (sub', again')) => (p ** v ** u'' ** (wrote, inV, sub', again'))
deeperMarkerHolds held x marked spine el named (MkVar (Later w)) i' d' named' u read = held (MkVar w) i' d' named' u read

||| A path one field longer is one match deeper: the marker of field k of a
||| match on a part, `markerAt i (path ++ [k])`, reads one level below the
||| part's own, `Var i (length path)`.
export
0 pathStep : (path : List Nat) -> (k : Nat) -> length (path ++ [k]) = S (length path)
pathStep [] k = Refl
pathStep (_ :: path) k = cong S (pathStep path k)

||| One marker per field: where a match on the marker for x, the part of
||| the writer's parameter i at `path`, which reads as `Var i (length
||| path)`, meets the data constructor the instance's value for x is
||| applied (`Spine`), each field is put in for a marker of its own, the
||| part at its field below, `path ++ [k]`, which reads one match deeper
||| (`pathStep`): here y, for the field f. Where the markers held the
||| instance's values, they hold with that field's added. Any reading of
||| the field is a child of a reading of the constructor applied (`SData`,
||| the other fields read as any term is: `readsAnyAll`), which the markers
||| hold as another reading of a part of a value of V, so the field is
||| another reading of a part of that value one level deeper
||| (`Proof.Bound.fieldHolds`). The markers' names, fresh and apart, are the
||| walk's.
export
0 fieldMarkerHolds : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {ctx : Frozen} ->
                     {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
                     MarkersHold m s ctx stands bs vs -> (x : Var ns) ->
                     walkMarker stands (replacedAt bs x) = Just (Template.Var i (length path)) ->
                     Spine (Var.index vs x) (Ref fc (DataCon tag arity) cn) fields -> Elem f fields ->
                     walkMarker stands y = Just (Template.Var i (length (path ++ [k]))) ->
                     MarkersHold m s ctx stands (Add new y bs) (f :: vs)
fieldMarkerHolds {path} {k} held x marked spine el named =
  deeperMarkerHolds held x marked spine el
    (replace {p = \l => walkMarker stands y = Just (Template.Var i l)} (pathStep path k) named)

------------------------------------------------------------------------------
-- A builtin's constant
------------------------------------------------------------------------------

||| What an instance reads a constant as, applied to nothing.
public export
constantRead : Constant -> Template
constantRead c = appliedConstant c []

||| What an instance reads some constants as, in order.
public export
constantsRead : Vect n Constant -> List Template
constantsRead [] = []
constantsRead (c :: cs) = constantRead c :: constantsRead cs

||| An instance reads a constant as `constantRead`: no closed run is one.
export
0 constantReadAs : ReadAs (InstanceMode ctx) env (PrimVal fc c) r -> r = constantRead c
constantReadAs (ASpine (SConstant [])) = Refl
constantReadAs (ARun run) = void (runNotConstant run)

-- A text read a leaf per character has as many.
0 speltLength : (cs : List Char) -> length (spelt cs ++ []) = length cs
speltLength [] = Refl
speltLength (_ :: cs) = cong S (speltLength cs)

0 eqMeasured : a = b -> (Nat.LTE b a, Nat.LTE a (S b))
eqMeasured Refl = (reflexive, lteSuccRight reflexive)

-- An integer's one symbol weighs one more than its magnitude.
0 integerMeasured : (k : Nat) -> (Nat.LTE k (S k + 0), Nat.LTE (S k + 0) (S k))
integerMeasured k = (lteSuccRight (lteAddRight k), LTESucc (rewrite plusZeroRightNeutral k in reflexive))

||| What a constant's template measures (`measureOf`) against what the
||| host's bound measures of it (`constantSize`): at least that, and at most
||| one more, an integer's one symbol weighing one more than its magnitude.
export
0 constantMeasured : (c : Constant) ->
                     (Nat.LTE (constantSize c) (measureOf (constantRead c)), Nat.LTE (measureOf (constantRead c)) (S (constantSize c)))
constantMeasured (I x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (I8 x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (I16 x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (I32 x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (I64 x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (BI x) = integerMeasured (magnitudeOf x)
constantMeasured (B8 x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (B16 x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (B32 x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (B64 x) = integerMeasured (magnitudeOf (cast x))
constantMeasured (Str x) = eqMeasured (speltLength (unpack x))
constantMeasured (Db x) = eqMeasured (speltLength (unpack (show x)))
constantMeasured (Ch _) = (LTEZero, LTEZero)
constantMeasured (PrT _) = (LTEZero, LTEZero)
constantMeasured WorldVal = (LTEZero, LTEZero)

-- Constants each measuring within a bound: each of their sizes is within it.
0 sizesBelow : (cs : Vect n Constant) -> Nat.LTE (measuresOf (constantsRead cs)) y ->
               SizesWithin (map Host.constantSize cs) (replicate n y)
sizesBelow [] _ = NoSizes
sizesBelow (c :: cs) le =
  SizeWithin (transitive (fst (constantMeasured c)) (transitive (maximumLeftUpperBound _ _) le))
             (sizesBelow cs (transitive (maximumRightUpperBound _ _) le))

||| The premise `Proof.Bound.AtComputed` asks of what an instance writes
||| where a site reads a builtin beside its call: the constant the host's
||| table computes from the constants it is given measures no more than
||| `grown` of the most they measure, as the instance reads each.
export
0 computedMeasured : {arity : Nat} -> (op : PrimFn arity) -> (cs : Vect arity Constant) -> tableOf op cs = Just c ->
                     Nat.LTE (measureOf (constantRead c)) (grown (measuresOf (constantsRead cs)))
computedMeasured op cs computed = transitive (snd (constantMeasured c)) (computedGrown op cs computed (sizesBelow cs reflexive))

------------------------------------------------------------------------------
-- The graph's rewrites of a reading
------------------------------------------------------------------------------

||| A dictionary read as a callee is given it (`asGiven`): what the instance
||| writes under its reading, it writes under the choice that reading is a
||| leaf of.
export
0 asGivenWrites : (k : Maybe ChoiceHead) -> (root : Root) -> Writes m s t w -> Writes m s (asGiven k (t, root)) w
asGivenWrites (Just k) (Readings.Chosen _) wr = Bound.Chosen Here wr
asGivenWrites (Just k) (Rooted _) wr = wr
asGivenWrites (Just k) (Gives _) wr = wr
asGivenWrites (Just k) (Parameter _ _) wr = wr
asGivenWrites (Just k) Unrooted wr = wr
asGivenWrites Nothing _ wr = wr

------------------------------------------------------------------------------
-- Where a part of a site's template is reached
------------------------------------------------------------------------------

||| Where a part sits in a template, as what an instance writes reaches it:
||| itself, a head's child, a recursion's argument, a choice's leaf, an
||| applied or computing family's argument. A choice's scrutinee and a
||| field's record are no such place: nothing an instance writes is read
||| off them, and they weigh no parameter (`occurrences`).
public export
data Reaches : Template -> Template -> Type where
  ReachesItself : Reaches t t
  ReachesChild : Elem c ts -> Reaches c u -> Reaches (Head a ts) u
  ReachesRecursion : Elem c ts -> Reaches c u -> Reaches (Opaque a ts) u
  ReachesLeaf : Elem c ls -> Reaches c u -> Reaches (Choice x ls) u
  ReachesApplied : Elem c ts -> Reaches c u -> Reaches (Applied i d ts) u
  ReachesComputing : Elem c ts -> Reaches c u -> Reaches (Computing i d ts) u

||| A part of a part reached is reached.
export
0 reachedBelow : Reaches t u -> Reaches u v -> Reaches t v
reachedBelow ReachesItself r = r
reachedBelow (ReachesChild el x) r = ReachesChild el (reachedBelow x r)
reachedBelow (ReachesRecursion el x) r = ReachesRecursion el (reachedBelow x r)
reachedBelow (ReachesLeaf el x) r = ReachesLeaf el (reachedBelow x r)
reachedBelow (ReachesApplied el x) r = ReachesApplied el (reachedBelow x r)
reachedBelow (ReachesComputing el x) r = ReachesComputing el (reachedBelow x r)

||| An argument of a family's closed reading, below its k heads.
export
0 raisedChild : (k : Nat) -> Elem x ts -> Reaches (raise k (Head Nothing ts)) x
raisedChild Z el = ReachesChild el ReachesItself
raisedChild (S k) el = ReachesChild Here (raisedChild k el)

||| Each argument of a family applied at a node, however its landing reads
||| it (`landedAs`), is reached from it: below k heads, as an applied
||| family's or a computing family's argument.
export
0 landedArgument : (l : Landing) -> (b : Template.Beta) -> Elem x ts -> Reaches (landedAs l b i d ts).template x
landedArgument Computed b el = ReachesComputing el ReachesItself
landedArgument (Evaluable _) b el = ReachesComputing el ReachesItself
landedArgument (Closed _) Template.Computes el = ReachesComputing el ReachesItself
landedArgument Open Template.Computes el = ReachesComputing el ReachesItself
landedArgument (Closed k) Template.Inert el = raisedChild k el
landedArgument Open Template.Inert el = ReachesApplied el ReachesItself

-- Lists' own facts about membership in an append.
0 inFront : Elem x xs -> Elem x (xs ++ ys)
inFront Here = Here
inFront (There el) = There (inFront el)

0 behind : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
behind [] el = el
behind (_ :: xs) el = There (behind xs el)

-- An occurrence in one of some templates is one in all of them.
0 occursAmong : {e : Nat} -> {cs : List Template} -> Elem c cs -> Elem x (occurrences e c) -> Elem x (occurrencesIn e cs)
occursAmong {cs = _ :: _} Here el = inFront el
occursAmong {cs = y :: _} (There k) el = behind (occurrences e y) (occursAmong k el)

0 stuckAmong : {cs : List Template} -> Elem c cs -> Elem x (stuck c) -> Elem x (stuckIn cs)
stuckAmong {cs = _ :: _} Here el = inFront el
stuckAmong {cs = y :: _} (There k) el = behind (stuck y) (stuckAmong k el)

mutual
  ||| A computing family reached in a template is weighed Stuck there,
  ||| however deep: its own occurrence, `(i, Stuck)`, is listed wherever
  ||| the template's occurrences are, and under a recursion or an applied
  ||| family's argument every marker is.
  export
  0 reachedOccurs : {e : Nat} -> Reaches t (Computing i d ts) -> Elem (i, Stuck) (occurrences e t)
  reachedOccurs ReachesItself = Here
  reachedOccurs (ReachesChild el r) = occursAmong el (reachedOccurs r)
  reachedOccurs (ReachesRecursion el r) = stuckAmong el (reachedStuck r)
  reachedOccurs (ReachesLeaf el r) = occursAmong el (reachedOccurs r)
  reachedOccurs (ReachesApplied el r) = There (stuckAmong el (reachedStuck r))
  reachedOccurs (ReachesComputing el r) = There (stuckAmong el (reachedStuck r))

  0 reachedStuck : Reaches t (Computing i d ts) -> Elem (i, Stuck) (stuck t)
  reachedStuck ReachesItself = Here
  reachedStuck (ReachesChild el r) = stuckAmong el (reachedStuck r)
  reachedStuck (ReachesRecursion el r) = stuckAmong el (reachedStuck r)
  reachedStuck (ReachesLeaf el r) = stuckAmong el (reachedStuck r)
  reachedStuck (ReachesApplied el r) = There (stuckAmong el (reachedStuck r))
  reachedStuck (ReachesComputing el r) = There (stuckAmong el (reachedStuck r))

------------------------------------------------------------------------------
-- The landings
------------------------------------------------------------------------------

||| What the graph's builder establishes of a site of its model, and of
||| the landings its template is read at (`withClosedFamilies`), for the
||| rewrite to keep what an instance writes:
||| - the graph is feasible (`feasible`), and holds the site's own arcs
|||   (`ownDrawn`, which `Proof.Describes.ownDrawnOf` gives every site of a
|||   model drawn from sites);
||| - the writer reads every parameter the template weighs with an arc at a
|||   position (`writersListed`), as every site of a built graph does
|||   (`Graph.Built.writersListed`), and every family the reading landed
|||   closed, which the template no longer names, as well
|||   (`Graph.SiteLanding`): so a family the rewrite drops is still read
|||   at the position its values land at, which `Beta`, `GivenPart` and
|||   `closedLands` name;
||| - only closed values no higher than k land at each position the writer
|||   reads a family landing closed at (`closedLands`): the site's landing
|||   is read off the graph's table of what landed at each numbered
|||   position (`Graph.SiteLanding`'s `readsTable`), where a closed entry
|||   leaves the position uncapped (`Graph.Built.uncappedLanded`) and
|||   bounds every site into it (`Graph.Built.targetsBounded`), each
|||   argument's closed landing an unmarked template no higher than k
|||   (`Graph.closedSelfBounded`);
||| - an applied parameter whose reading roots an implementation lands
|||   other than closed, and the roots it is read with are read off its
|||   head, whatever its arguments (`appliedRoots`): `Heads.roots` reads an
|||   applied marker by its index alone, and roots it only where it lands
|||   open (`Heads.appliedRootsOf`);
||| - the roots a field's record gives are kept by the rewrite
|||   (`recordRoots`, `Heads.recordRootsOf`): a use of the writer's
|||   dictionary parameter applied reads as the parameter whatever its
|||   arguments compute, so a record read as computing roots what it did
|||   as written, and the graph draws the field read's arcs.
||| A built graph gives each of its sites all of these but the
||| feasibility, which the checker's success gives (`builtLandings`).
||| A family read as computing is then never reached where an instance
||| writes (`computingUnreached`): it weighs its parameter Stuck, the arc
||| from the position the writer reads it at is Unmeasured, and no feasible
||| potential meets one.
public export
record LandingsWrite {g : Graph} (m : Model g) (s : Bound.Site g.size) (c : Nat -> Landing) where
  constructor MkLandingsWrite
  0 potential : Vect g.size Nat
  0 feasible : Feasible g potential
  0 ownDrawn : (a : Arc g.size) -> Elem a (ownArcs s) -> Elem a g.arcs
  0 writersListed : WritersListed s
  0 closedLands : (i, k : Nat) -> c i = Closed k -> (p : Fin g.size) -> Elem (i, p) s.writers -> Lands g m p k
  0 appliedRoots : AppliedRoots c s.roots
  0 recordRoots : RecordRoots c s.roots

||| Only closed values no higher than k land at a position a site of a
||| built graph reads a parameter at where its landing reads closed values
||| no higher than k: the table it read that landing off holds closed
||| values no higher there, which leaves the position uncapped and bounds
||| every site into it.
export
0 closedLandsOf : (b : Built) -> {s : Bound.Site b.graph.size} -> (inModel : Elem s b.model.sites) ->
                  (i, k : Nat) -> (b.landedSites s inModel).atParameter i = Closed k ->
                  (p : Fin b.graph.size) -> Elem (i, p) s.writers -> Lands b.graph b.model p k
closedLandsOf b {s} inModel i k read p wrote = case (b.landedSites s inModel).readsTable i k read p wrote of
  (k' ** (atP, le)) =>
    MkLands (b.uncappedLanded p k' atP)
            (\s', el, toP => case b.targetsBounded s' el k' (replace {p = \q => Vect.index q b.landings = Just (Closed k')} (sym toP) atP) of
                              (um, high) => (um, transitive high le))

||| What a built graph gives the rewrite of one of its sites, read where
||| its writer's parameters land as its table says (`Graph.SiteLanding`):
||| its own arcs (`Built.ownDrawn`), its writers listing every parameter
||| its template weighs with an arc (`Built.writersListed`), what lands
||| where its landing reads closed values (`closedLandsOf`), and its roots'
||| word on an applied use and on a field's record; the graph's
||| feasibility is the checker's success.
export
0 builtLandings : (b : Built) -> {s : Bound.Site b.graph.size} -> (inModel : Elem s b.model.sites) ->
                  (pot : Vect b.graph.size Nat) -> Feasible b.graph pot ->
                  LandingsWrite b.model s (b.landedSites s inModel).atParameter
builtLandings b {s} inModel pot fe =
  MkLandingsWrite pot fe (b.ownDrawn s inModel) (b.writersListed s inModel) (closedLandsOf b inModel)
                  (b.landedSites s inModel).appliedRoots (b.landedSites s inModel).recordRoots

||| A family read as computing is reached nowhere an instance writes in a
||| site's template: reached, it weighs its parameter Stuck
||| (`reachedOccurs`), so its writer reads it at a position
||| (`writersListed`) whose arc is Unmeasured, which the feasible graph
||| holding it does not admit (`Proof.Describes.stuckUnread`).
export
0 computingUnreached : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {c : Nat -> Landing} ->
                       LandingsWrite m s c -> Reaches s.template (Computing i d ts) -> Void
computingUnreached ls r = case weightsCover s.template (reachedOccurs {e = 0} r) of
  (v ** (inW, dom)) => case overStuck dom of
    Refl => case ls.writersListed i Stuck inW Unmeasured Refl of
      (p ** wp) => stuckUnread ls.feasible s ls.ownDrawn inW wp

||| What writes a family of the writer's applied, its arguments' writes
||| already carried to the rewritten arguments.
public export
data AppliedWrites : {g : Graph} -> Model g -> Bound.Site g.size -> (i, d : Nat) -> (ts, ts' : List Template) -> Template -> Type where
  ByBeta : Elem (i, p) s.writers -> InV m p v -> Sub d v f -> Within f body -> AllWrite m s ts' ws ->
           Instantiates ws body w -> AppliedWrites m s i d ts ts' w
  ByPart : Elem (i, p) s.writers -> InV m p v -> Sub d v f -> Within f w -> AppliedWrites m s i d ts ts' w
  ByMember : Elem j (s.roots (Applied i d ts)) -> Arguments m j 0 as -> AppliedWrites m s i d ts ts' (Head (Just j) as)

-- A family applied, rewritten: what wrote it writes it as the landing
-- reads it, where the rewritten node is reached in the site's template.
-- Read as computing, it is reached nowhere (`computingUnreached`).
0 appliedLanded : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {c : Nat -> Landing} -> LandingsWrite m s c ->
                  (l : Landing) -> c i = l -> (b : Template.Beta) ->
                  Reaches s.template (landedAs l b i d (allWithClosed c ts)).template ->
                  AppliedWrites m s i d ts (allWithClosed c ts) w -> Writes m s (landedAs l b i d (allWithClosed c ts)).template w
appliedLanded ls Open isOpen Template.Inert r (ByBeta wrote inV sub within aw inst) = Bound.Beta wrote inV sub within aw inst
appliedLanded ls Open isOpen Template.Inert r (ByPart wrote inV sub within) = GivenPart wrote inV sub within
appliedLanded {i} {d} {ts} {c} ls Open isOpen Template.Inert r (ByMember {j} rooted args) =
  MemberOf (snd (ls.appliedRoots i d ts j rooted) (allWithClosed c ts)) args
appliedLanded {i} ls (Closed k) isClosed Template.Inert r (ByBeta {p} wrote inV sub within aw inst) =
  Landed (ls.closedLands i k isClosed p wrote) inV sub within aw inst
appliedLanded {i} ls (Closed k) isClosed Template.Inert r (ByPart {p} wrote inV sub within) =
  LandedMember (ls.closedLands i k isClosed p wrote) inV sub within
appliedLanded {i} {d} {ts} ls (Closed k) isClosed Template.Inert r (ByMember {j} rooted args) =
  void (fst (ls.appliedRoots i d ts j rooted) k isClosed)
appliedLanded ls Computed _ b r wr = void (computingUnreached ls r)
appliedLanded ls (Evaluable es) _ b r wr = void (computingUnreached ls r)
appliedLanded ls (Closed k) _ Template.Computes r wr = void (computingUnreached ls r)
appliedLanded ls Open _ Template.Computes r wr = void (computingUnreached ls r)

-- A leaf of a choice, rewritten, is a leaf of the choice rewritten.
0 closedElem : {c : Nat -> Landing} -> Elem x ls -> Elem (withClosedFamilies c x) (allWithClosed c ls)
closedElem Here = Here
closedElem (There el) = There (closedElem el)

-- Heads above a template, rewritten, are heads above it rewritten.
0 closedRaise : {c : Nat -> Landing} -> (k : Nat) -> (t : Template) ->
                withClosedFamilies c (raise k t) = raise k (withClosedFamilies c t)
closedRaise Z t = Refl
closedRaise (S k) t = cong (\u => Head Nothing [u]) (closedRaise k t)

mutual
  ||| The graph reads a site's template with each family of the writer's
  ||| applied as its landing says (`withClosedFamilies`): what an instance
  ||| writes under the reading at a part of it, it writes under that part
  ||| rewritten, wherever the rewritten part is reached in the template the
  ||| site holds, where the builder establishes the landings
  ||| (`LandingsWrite`).
  export
  0 closedWrites : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {c : Nat -> Landing} -> LandingsWrite m s c ->
                   Reaches s.template (withClosedFamilies c t) -> Writes m s t w -> Writes m s (withClosedFamilies c t) w
  closedWrites ls r (AtVar wrote inV sub again) = AtVar wrote inV sub again
  closedWrites ls r (AtHead aw) = AtHead (allClosedWrites ls (\el => reachedBelow r (ReachesChild el ReachesItself)) aw)
  closedWrites ls r (AtOpaque aw) = AtOpaque (allClosedWrites ls (\el => reachedBelow r (ReachesRecursion el ReachesItself)) aw)
  closedWrites ls r AtLeaf = AtLeaf
  closedWrites ls r (AtRunRead run) = AtRunRead run
  closedWrites ls r (AtComputed aw form measured) =
    AtComputed (allClosedWrites ls (\el => reachedBelow r (ReachesLeaf Here (ReachesChild el ReachesItself))) aw) form measured
  closedWrites ls r (AtRun wr run) = AtRun (closedWrites ls (reachedBelow r (ReachesChild Here ReachesItself)) wr) run
  closedWrites ls r (AtCut wr high) = AtCut (closedWrites ls r wr) high
  closedWrites ls r AtToken = AtToken
  closedWrites ls r AtFormal = AtFormal
  closedWrites {c} ls r (Bound.Chosen el wr) =
    Bound.Chosen (closedElem {c} el) (closedWrites ls (reachedBelow r (ReachesLeaf (closedElem {c} el) ReachesItself)) wr)
  closedWrites {c} ls r (AtContracted el wr drops) =
    AtContracted (closedElem {c} el) (closedWrites ls (reachedBelow r (ReachesChild (closedElem {c} el) ReachesItself)) wr) drops
  closedWrites {c} ls r (Bound.Beta {i} {d} {ts} wrote inV sub within aw inst) =
    appliedLanded {i} {d} {ts} ls (c i) Refl (argumentsBeta c (allWithClosed c ts)) r
                  (ByBeta wrote inV sub within
                     (allClosedWrites ls (\el => reachedBelow r (landedArgument {i} {d} (c i) (argumentsBeta c (allWithClosed c ts)) el)) aw)
                     inst)
  closedWrites {c} ls r (GivenPart {i} {d} {ts} wrote inV sub within) =
    appliedLanded {i} {d} {ts} ls (c i) Refl (argumentsBeta c (allWithClosed c ts)) r (ByPart wrote inV sub within)
  closedWrites {c} ls r (MemberOf {i} {d} {ts} rooted args) =
    appliedLanded {i} {d} {ts} ls (c i) Refl (argumentsBeta c (allWithClosed c ts)) r (ByMember rooted args)
  closedWrites {s} {c} ls r (Landed {k} {ts} lands inV sub within aw inst) =
    let r' = replace {p = Reaches s.template} (closedRaise {c} k (Head Nothing ts)) r in
    rewrite closedRaise {c} k (Head Nothing ts) in
      Landed lands inV sub within (allClosedWrites ls (\el => reachedBelow r' (raisedChild k el)) aw) inst
  closedWrites {c} ls r (LandedMember {k} {ts} lands inV sub within) =
    rewrite closedRaise {c} k (Head Nothing ts) in LandedMember lands inV sub within
  closedWrites ls r (AtField {r = rd} {j} rooted at inV) = AtField (ls.recordRoots rd j rooted) at inV
  closedWrites ls r (AtMember at inV renumbered) = AtMember at inV renumbered
  closedWrites ls r (AtHeldHole at inV high within) = AtHeldHole at inV high within

  0 allClosedWrites : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {c : Nat -> Landing} -> LandingsWrite m s c ->
                      ({x : Template} -> Elem x (allWithClosed c ts) -> Reaches s.template x) ->
                      AllWrite m s ts ws -> AllWrite m s (allWithClosed c ts) ws
  allClosedWrites ls under [] = []
  allClosedWrites ls under (wr :: aw) = closedWrites ls (under Here) wr :: allClosedWrites ls (\el => under (There el)) aw

------------------------------------------------------------------------------
-- Two readings of one term
------------------------------------------------------------------------------

||| What two readings substitute for one scope's variables: at each place,
||| an argument of a family's value in both, whatever its number, or a
||| placeholder in both.
public export
data SameKinds : Values Substitute vs -> Values Substitute vs -> Type where
  NoKinds : SameKinds [] []
  BothFormal : SameKinds env env' -> SameKinds (FormalArgument j k :: env) (FormalArgument j' k' :: env')
  BothPlaceholding : SameKinds env env' -> SameKinds (Placeholding :: env) (Placeholding :: env')

0 sameKindsAt : SameKinds env env' -> (idx : Nat) -> (0 p : IsVar x idx vs) ->
                Reread (substituteTemplate (valueAt env idx p)) (substituteTemplate (valueAt env' idx p))
sameKindsAt (BothFormal _) Z _ = RereadFormal
sameKindsAt (BothPlaceholding _) Z _ = RereadSame
sameKindsAt (BothFormal same) (S i) p = sameKindsAt same i (dropLater p)
sameKindsAt (BothPlaceholding same) (S i) p = sameKindsAt same i (dropLater p)
sameKindsAt NoKinds _ First impossible
sameKindsAt NoKinds _ (Later _) impossible

0 allAppend : AllReread as as' -> AllReread bs bs' -> AllReread (as ++ bs) (as' ++ bs')
allAppend NoneReread ys = ys
allAppend (EachReread x xs) ys = EachReread x (allAppend xs ys)

0 allSame : (ts : List Template) -> AllReread ts ts
allSame [] = NoneReread
allSame (t :: ts) = EachReread RereadSame (allSame ts)

-- A part applied, read again: one node over it and its arguments.
0 partAlike : Reread t t' -> AllReread ts ts' -> Reread (partOf EveryNode t ts) (partOf EveryNode t' ts')
partAlike r NoneReread = r
partAlike r (EachReread x xs) = RereadHead (EachReread r (EachReread x xs))

0 constantAlike : (c : Constant) -> AllReread ts ts' -> Reread (appliedConstant c ts) (appliedConstant c ts')
constantAlike (Str x) rs = RereadHead (allAppend (allSame (spelt (unpack x))) rs)
constantAlike (Db x) rs = RereadHead (allAppend (allSame (spelt (unpack (show x)))) rs)
constantAlike (I _) rs = partAlike RereadSame rs
constantAlike (I8 _) rs = partAlike RereadSame rs
constantAlike (I16 _) rs = partAlike RereadSame rs
constantAlike (I32 _) rs = partAlike RereadSame rs
constantAlike (I64 _) rs = partAlike RereadSame rs
constantAlike (BI _) rs = partAlike RereadSame rs
constantAlike (B8 _) rs = partAlike RereadSame rs
constantAlike (B16 _) rs = partAlike RereadSame rs
constantAlike (B32 _) rs = partAlike RereadSame rs
constantAlike (B64 _) rs = partAlike RereadSame rs
constantAlike (Ch _) rs = partAlike RereadSame rs
constantAlike (PrT _) rs = partAlike RereadSame rs
constantAlike WorldVal rs = partAlike RereadSame rs

0 runOnce : Run u k -> Run u k' -> k = k'
runOnce Literals.RunZero Literals.RunZero = Refl
runOnce (RunSucc r) (RunSucc r') = cong S (runOnce r r')

-- No binder an instance reads as a node is a lambda.
0 lambdaBinder : BinderAs m env (Lam fc rig info ty) ps -> Void
lambdaBinder (BLet _ _) impossible
lambdaBinder (BPi _ _) impossible
lambdaBinder (BPVar _ _) impossible
lambdaBinder (BPLet _ _) impossible
lambdaBinder (BPVTy _) impossible

mutual
  -- A closed run read node by node: a run read so, each part of it
  -- possibly a closed run's leaf again.
  0 runRead : Run u k -> ReadAs (InstanceMode ctx) env u t -> RunRead (S k) t
  runRead run (ARun run') = rewrite runOnce run run' in RunReadLeaf
  runRead run (ASpine s) = runSpineRead run s

  0 runSpineRead : Run u k -> SpineAs (InstanceMode ctx) env u [] t -> RunRead (S k) t
  runSpineRead Literals.RunZero (SData _ []) = RunReadZero
  runSpineRead (RunSucc run) (SApp (SData _ (r :: []))) = RunReadSucc (runRead run r)

mutual
  ||| Two readings of one term as an instance's, over substitutes of the
  ||| same kinds, are one reading but for an argument of a family's value,
  ||| numbered by its binders, and a closed run, read as its leaf or node
  ||| by node (`Proof.Bound.Reread`): every other node is read by its head,
  ||| one way.
  export
  0 readsAlike : SameKinds env env' -> ReadAs (InstanceMode ctx) env t u -> ReadAs (InstanceMode ctx) env' t u' -> Reread u u'
  readsAlike same (ARun r) (ARun r') = rewrite runOnce r r' in RereadSame
  readsAlike same (ARun r) (ASpine s) = RereadAsRun (runSpineRead r s)
  readsAlike same (ASpine s) (ARun r) = RereadAsLeaf (runSpineRead r s)
  readsAlike same (ASpine s) (ASpine s') = spinesAlike same s s'

  0 allAlike : SameKinds env env' -> AllReadAs (InstanceMode ctx) env as ts -> AllReadAs (InstanceMode ctx) env' as ts' ->
               AllReread ts ts'
  allAlike same [] [] = NoneReread
  allAlike same (x :: xs) (y :: ys) = EachReread (readsAlike same x y) (allAlike same xs ys)

  0 passingAlike : SameKinds env env' -> PassingAs (InstanceMode ctx) env info ps -> PassingAs (InstanceMode ctx) env' info ps' ->
                   AllReread ps ps'
  passingAlike same PImplicit PImplicit = NoneReread
  passingAlike same PExplicit PExplicit = NoneReread
  passingAlike same PAuto PAuto = NoneReread
  passingAlike same (PDefault x) (PDefault y) = EachReread (readsAlike same x y) NoneReread

  0 binderAlike : SameKinds env env' -> BinderAs (InstanceMode ctx) env b ps -> BinderAs (InstanceMode ctx) env' b ps' ->
                  AllReread ps ps'
  binderAlike same (BLet x y) (BLet x' y') = EachReread (readsAlike same x x') (EachReread (readsAlike same y y') NoneReread)
  binderAlike same (BPi pa x) (BPi pa' x') = allAppend (passingAlike same pa pa') (EachReread (readsAlike same x x') NoneReread)
  binderAlike same (BPVar pa x) (BPVar pa' x') = allAppend (passingAlike same pa pa') (EachReread (readsAlike same x x') NoneReread)
  binderAlike same (BPLet x y) (BPLet x' y') = EachReread (readsAlike same x x') (EachReread (readsAlike same y y') NoneReread)
  binderAlike same (BPVTy x) (BPVTy x') = EachReread (readsAlike same x x') NoneReread

  0 spinesAlike : SameKinds env env' -> SpineAs (InstanceMode ctx) env t as u -> SpineAs (InstanceMode ctx) env' t as u' ->
                  Reread u u'
  spinesAlike same (SApp s) (SApp s') = spinesAlike same s s'
  spinesAlike same (SDot x xs) (SDot y ys) = RereadHead (EachReread (readsAlike same x y) (allAlike same xs ys))
  spinesAlike same (SPlaceholder xs) (SPlaceholder ys) = partAlike RereadSame (allAlike same xs ys)
  spinesAlike same (SImpossible xs) (SImpossible ys) = partAlike RereadSame (allAlike same xs ys)
  spinesAlike same (SLocal {idx} {p} xs) (SLocal ys) = partAlike (sameKindsAt same idx p) (allAlike same xs ys)
  spinesAlike same (SMeta ms xs) (SMeta ms' ys) = RereadHead (allAppend (allAlike same ms ms') (allAlike same xs ys))
  spinesAlike same (SUniverse xs) (SUniverse ys) = partAlike RereadSame (allAlike same xs ys)
  spinesAlike same (SConstant {c} xs) (SConstant ys) = constantAlike c (allAlike same xs ys)
  spinesAlike same (SLambda pa x sc xs) (SLambda pa' y sc' ys) =
    RereadHead (allAppend (allAppend (passingAlike same pa pa')
                                     (EachReread (readsAlike same x y) (EachReread (readsAlike (BothFormal same) sc sc') NoneReread)))
                          (allAlike same xs ys))
  spinesAlike same (SLambda _ _ _ _) (SBinder ba _ _) = void (lambdaBinder ba)
  spinesAlike same (SBinder ba _ _) (SLambda _ _ _ _) = void (lambdaBinder ba)
  spinesAlike same (SBinder ba sc xs) (SBinder ba' sc' ys) =
    RereadHead (allAppend (allAppend (binderAlike same ba ba') (EachReread (readsAlike (BothPlaceholding same) sc sc') NoneReread))
                          (allAlike same xs ys))
  spinesAlike same (SDelayed x xs) (SDelayed y ys) = RereadHead (EachReread (readsAlike same x y) (allAlike same xs ys))
  spinesAlike same (SDelay x a xs) (SDelay y b ys) =
    RereadHead (EachReread (readsAlike same x y) (EachReread (readsAlike same a b) (allAlike same xs ys)))
  spinesAlike same (SForce x xs) (SForce y ys) = RereadHead (EachReread (readsAlike same x y) (allAlike same xs ys))
  spinesAlike same (SAs x a xs) (SAs y b ys) =
    RereadHead (EachReread (readsAlike same x y) (EachReread (readsAlike same a b) (allAlike same xs ys)))
  spinesAlike same (SHole hole xs) (SHole hole' ys) =
    rewrite justSame (trans (sym hole) hole') in partAlike RereadSame (allAlike same xs ys)
  spinesAlike same (SHole hole _) (SFormal none _ _) = void (justNotNothing (trans (sym hole) none))
  spinesAlike same (SHole hole _) (SPart none _ _) = void (justNotNothing (trans (sym hole) none))
  spinesAlike same (SFormal none _ _) (SHole hole _) = void (justNotNothing (trans (sym hole) none))
  spinesAlike same (SFormal _ _ xs) (SFormal _ _ ys) = partAlike RereadFormal (allAlike same xs ys)
  spinesAlike same (SFormal {j} {k} _ formal _) (SPart _ plain _) = void (plain j k formal)
  spinesAlike same (SPart none _ _) (SHole hole _) = void (justNotNothing (trans (sym hole) none))
  spinesAlike same (SPart _ plain _) (SFormal {j} {k} _ formal _) = void (plain j k formal)
  spinesAlike same (SPart _ _ xs) (SPart _ _ ys) = partAlike RereadSame (allAlike same xs ys)
  spinesAlike same (SNoDefinition _ xs) (SNoDefinition _ ys) = partAlike RereadSame (allAlike same xs ys)
  spinesAlike same (SNoDefinition none _) (SKept at _) = void (nothingNotJust (trans (sym none) at))
  spinesAlike same (SKept at _) (SNoDefinition none _) = void (nothingNotJust (trans (sym none) at))
  spinesAlike same (SKept at xs) (SKept at' ys) =
    rewrite justSame (trans (sym at) at') in RereadHead (allAlike same xs ys)
  spinesAlike same (SData at xs) (SData at' ys) = rewrite trans (sym at) at' in RereadHead (allAlike same xs ys)
  spinesAlike same (STypeCon at xs) (STypeCon at' ys) = rewrite trans (sym at) at' in RereadHead (allAlike same xs ys)

------------------------------------------------------------------------------
-- Contraction is maximal
------------------------------------------------------------------------------

-- The variable a strengthening drops has no index after it.
0 droppedNotKept : Dropped o o j -> Void
droppedNotKept DropPast impossible
droppedNotKept DropBefore impossible
droppedNotKept (DropUnder d) = droppedNotKept d

mutual
  ||| A strengthening drops a variable only from a term that does not
  ||| mention it: the dropped variable has no index in the scope without it
  ||| (`Idris.Host.Dropped`), and every other node is rebuilt from its parts.
  export
  0 droppedUnmentioned : Strengthened o t u -> Mentions o t -> Void
  droppedUnmentioned (MLocal moved) MentionsLocal = droppedNotKept moved
  droppedUnmentioned (MMarker first _) _ = void (noneReplaces first)
  droppedUnmentioned (MMeta _ ms) (MentionsMeta mentioned) = anyDroppedUnmentioned ms mentioned
  droppedUnmentioned (MBind mb _) (MentionsBinder mentioned) = binderDroppedUnmentioned mb mentioned
  droppedUnmentioned (MBind _ ms) (MentionsScope mentioned) = droppedUnmentioned ms mentioned
  droppedUnmentioned (MApp mf _) (MentionsFunction mentioned) = droppedUnmentioned mf mentioned
  droppedUnmentioned (MApp _ ma) (MentionsArgument mentioned) = droppedUnmentioned ma mentioned
  droppedUnmentioned (MAs ma _) (MentionsAsName mentioned) = droppedUnmentioned ma mentioned
  droppedUnmentioned (MAs _ mt) (MentionsAsPattern mentioned) = droppedUnmentioned mt mentioned
  droppedUnmentioned (MDelayed mt) (MentionsDelayed mentioned) = droppedUnmentioned mt mentioned
  droppedUnmentioned (MDelay mty _) (MentionsDelayType mentioned) = droppedUnmentioned mty mentioned
  droppedUnmentioned (MDelay _ ma) (MentionsDelayValue mentioned) = droppedUnmentioned ma mentioned
  droppedUnmentioned (MForce mt) (MentionsForce mentioned) = droppedUnmentioned mt mentioned
  droppedUnmentioned (MDotted mt) (MentionsDotted mentioned) = droppedUnmentioned mt mentioned

  0 anyDroppedUnmentioned : AllMapped DropsOne None (the (SubstEnv [] []) []) o ts us -> AnyMentions o ts -> Void
  anyDroppedUnmentioned (MEach m _) (MentionedHere mentioned) = droppedUnmentioned m mentioned
  anyDroppedUnmentioned (MEach _ ms) (MentionedLater mentioned) = anyDroppedUnmentioned ms mentioned

  0 binderDroppedUnmentioned : BinderMapped DropsOne None (the (SubstEnv [] []) []) o b b' -> BinderMentions o b -> Void
  binderDroppedUnmentioned (MLam mp _) (MentionsLamInfo mentioned) = piDroppedUnmentioned mp mentioned
  binderDroppedUnmentioned (MLam _ mty) (MentionsLamType mentioned) = droppedUnmentioned mty mentioned
  binderDroppedUnmentioned (MLet mv _) (MentionsLetValue mentioned) = droppedUnmentioned mv mentioned
  binderDroppedUnmentioned (MLet _ mty) (MentionsLetType mentioned) = droppedUnmentioned mty mentioned
  binderDroppedUnmentioned (MPi mp _) (MentionsPiInfo mentioned) = piDroppedUnmentioned mp mentioned
  binderDroppedUnmentioned (MPi _ mty) (MentionsPiType mentioned) = droppedUnmentioned mty mentioned
  binderDroppedUnmentioned (MPVar mp _) (MentionsPVarInfo mentioned) = piDroppedUnmentioned mp mentioned
  binderDroppedUnmentioned (MPVar _ mty) (MentionsPVarType mentioned) = droppedUnmentioned mty mentioned
  binderDroppedUnmentioned (MPLet mv _) (MentionsPLetValue mentioned) = droppedUnmentioned mv mentioned
  binderDroppedUnmentioned (MPLet _ mty) (MentionsPLetType mentioned) = droppedUnmentioned mty mentioned
  binderDroppedUnmentioned (MPVTy mty) (MentionsPVTyType mentioned) = droppedUnmentioned mty mentioned

  0 piDroppedUnmentioned : PiMapped DropsOne None (the (SubstEnv [] []) []) o p p' -> PiMentions o p -> Void
  piDroppedUnmentioned (MDefault m) (MentionsDefault mentioned) = droppedUnmentioned m mentioned

-- A contraction of every redex keeps no call's redex.
0 noCallKept : KeptCall EveryRedex g -> Void
noCallKept (CallOf _ _) impossible

-- A lambda left with its reason to stay is no redex a contraction of every
-- redex contracts: its body applies nothing to its variable, or applies a
-- term that mentions it, which no strengthening drops it from.
0 leftNoRedex : LambdaLeft EveryRedex (App afc f (Local lfc l Z p)) -> Strengthened Z f g -> Void
leftNoRedex (NoRedex none) _ = absurd none
leftNoRedex (UsedByFunction mentioned) dropped = droppedUnmentioned dropped mentioned
leftNoRedex (CallKept why) _ = noCallKept why

-- No binder of its own node is a lambda.
0 lambdaNoBinder : BinderNormal how (Lam fc c p ty) -> Void
lambdaNoBinder (NormalLet _ _) impossible
lambdaNoBinder (NormalPi _) impossible
lambdaNoBinder (NormalPVar _) impossible
lambdaNoBinder (NormalPLet _ _) impossible
lambdaNoBinder (NormalPVTy _) impossible

mutual
  ||| Contraction is maximal: a term that holds no redex a contraction of
  ||| every redex contracts (`Contraction.EtaNormal`, which `Contraction.contractedBy`
  ||| gives what it returns) contracts to nothing but itself. An instance's
  ||| form is contracted so, so reading it again reads it as it is.
  export
  0 etaNormalFixed : EtaNormal EveryRedex t -> EtaContracts t u -> u = t
  etaNormalFixed _ EtaSame = Refl
  etaNormalFixed (NormalLambda _ nsc left) (EtaRedex body dropped) = case etaNormalFixed nsc body of
    Refl => void (leftNoRedex left dropped)
  etaNormalFixed (NormalBinder nb _) (EtaRedex _ _) = void (lambdaNoBinder nb)
  etaNormalFixed (NormalLambda nty nsc _) (EtaBind (EtaLam cty) csc) =
    case etaNormalFixed nty cty of
      Refl => case etaNormalFixed nsc csc of Refl => Refl
  etaNormalFixed (NormalBinder nb nsc) (EtaBind cb csc) =
    case binderNormalFixed nb cb of
      Refl => case etaNormalFixed nsc csc of Refl => Refl
  etaNormalFixed (NormalApp nf na) (EtaApp cf ca) =
    case etaNormalFixed nf cf of
      Refl => case etaNormalFixed na ca of Refl => Refl
  etaNormalFixed (NormalAs na nt) (EtaAs ca ct) =
    case etaNormalFixed na ca of
      Refl => case etaNormalFixed nt ct of Refl => Refl
  etaNormalFixed (NormalDelayed nt) (EtaDelayed ct) = case etaNormalFixed nt ct of
    Refl => Refl
  etaNormalFixed (NormalDelay nty na) (EtaDelay cty ca) =
    case etaNormalFixed nty cty of
      Refl => case etaNormalFixed na ca of Refl => Refl
  etaNormalFixed (NormalForce nt) (EtaForce ct) = case etaNormalFixed nt ct of
    Refl => Refl
  etaNormalFixed (NormalDotted nt) (EtaDotted ct) = case etaNormalFixed nt ct of
    Refl => Refl

  0 binderNormalFixed : BinderNormal EveryRedex b -> BinderContracts b b' -> b' = b
  binderNormalFixed (NormalLet nv nty) (EtaLet cv cty) =
    case etaNormalFixed nv cv of
      Refl => case etaNormalFixed nty cty of Refl => Refl
  binderNormalFixed (NormalPi nty) (EtaPi cty) = case etaNormalFixed nty cty of
    Refl => Refl
  binderNormalFixed (NormalPVar nty) (EtaPVar cty) = case etaNormalFixed nty cty of
    Refl => Refl
  binderNormalFixed (NormalPLet nv nty) (EtaPLet cv cty) =
    case etaNormalFixed nv cv of
      Refl => case etaNormalFixed nty cty of Refl => Refl
  binderNormalFixed (NormalPVTy nty) (EtaPVTy cty) = case etaNormalFixed nty cty of
    Refl => Refl

------------------------------------------------------------------------------
-- The markers along a request chain
------------------------------------------------------------------------------

||| The root request holds no marker: its instance has no static argument.
export
0 rootHolds : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> MarkersHold m s ctx stands None []
rootHolds (MkVar First) _ _ _ _ _ impossible
rootHolds (MkVar (Later _)) _ _ _ _ _ impossible

||| Where a requested instance's value for its parameter i, matched nowhere
||| (`Var i 0`), came from: the form an instance's reading of the request's
||| argument read, which a site of the model writes at a position the
||| requested node's site reads parameter i at, as the reading lemma at the
||| requesting instance's site gives (`siteWritesRead`).
public export
data ArgumentFrom : {g : Graph} -> Model g -> Bound.Site g.size -> Frozen -> (i, d : Nat) -> ClosedTerm -> Type where
  WrittenArgument : {0 k : Readings.Static} -> {0 t : ClosedTerm} -> (p : Fin g.size) -> Elem (i, p) s.writers ->
                    (inst : InstanceReading ctx k t) -> SiteWrites m p inst.template -> (0 _ : d = 0) -> (0 _ : v = inst.form) ->
                    ArgumentFrom m s ctx i d v

||| A request's step along its chain: where each marker of the requested
||| instance stands for a parameter whose argument a site wrote
||| (`ArgumentFrom`), the markers hold the instance's values. The value is
||| the reading's form; any reading of it is another reading of the
||| template the site wrote (`readsAlike`), a value of V there
||| (`Proof.Derivation.siteGives`), its own part at depth 0.
export
0 requestHolds : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {ctx : Frozen} ->
                 {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
                 ((x : Var ns) -> (i, d : Nat) -> walkMarker stands (replacedAt bs x) = Just (Template.Var i d) ->
                  ArgumentFrom m s ctx i d (Var.index vs x)) ->
                 MarkersHold m s ctx stands bs vs
requestHolds from x i d marked u read = case from x i d marked of
  WrittenArgument at wrote inst written Refl same =>
    (at ** inst.template ** inst.template **
      (wrote, siteGives written, Self,
       readsAlike NoKinds inst.describes (replace {p = \z => ReadAs (InstanceMode ctx) [] z u} same read)))

------------------------------------------------------------------------------
-- The reading lemma's induction
------------------------------------------------------------------------------

||| What the reading lemma's induction, on the site's reading of its form
||| (`ReadAs`), proves of each node of the form: where the node, closed by
||| its substitutes and the instance's values put in, reduces by an
||| evaluation's steps to a term that takes no step further, which the
||| instance contracts to an eta-normal term (`Contraction.EtaNormal`, what
||| `Contraction.contractedBy` gives) and reads, the node's template writes that
||| reading. `ReadingCovers` is this at the root, whose instance reading is
||| the form an `InstanceReading` holds.
public export
0 NodeCovers : {g : Graph} -> (m : Model g) -> Bound.Site g.size -> Evaluation -> Frozen -> Bounds ns -> SubstEnv ns [] ->
               ClosedTerm -> Template -> Type
NodeCovers {ns} m s ev ctx bs vs u t =
  {0 w, v : ClosedTerm} -> Reduces ev ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs u) w -> Irreducible ev ctx w ->
  EtaContracts w v -> EtaNormal EveryRedex v -> (r : Template) -> ReadAs (InstanceMode ctx) [] v r -> Writes m s t r

||| The induction at a marker of the writer's part, applied to nothing:
||| where the instance's reading of the term it reaches is its reading of
||| the value put in for the marker, that is what the markers hold
||| (`MarkersHold`), a part as deep as the marker reads of a value of V at
||| a position the writer reads the parameter at (`AtVar`).
export
0 markerWrites : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {ctx : Frozen} ->
                 {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
                 MarkersHold m s ctx stands bs vs -> (x : Var ns) ->
                 walkMarker stands (replacedAt bs x) = Just (Template.Var i d) ->
                 ReadAs (InstanceMode ctx) [] (Var.index vs x) u -> Writes m s (Template.Var i d) u
markerWrites held x marked read = case held x i d marked u read of
  (p ** v ** u' ** (wrote, inV, sub, again)) => AtVar wrote inV sub again

------------------------------------------------------------------------------
-- The reading lemma at the root, and at the graph's site
------------------------------------------------------------------------------

||| The kinds read off the host's normal form alone: a type, a family, a
||| form; no reading reads one as written (`Readings.ReadAsWritten`).
public export
data ReadOffNormal : Readings.Static -> Type where
  TypeReadNormal : ReadOffNormal AType
  FamilyReadNormal : ReadOffNormal AFamily
  FormReadNormal : ReadOffNormal AForm

0 notWritten : ReadOffNormal k -> ReadAsWritten k -> Void
notWritten TypeReadNormal WrittenDictionary impossible
notWritten TypeReadNormal WrittenShape impossible
notWritten FamilyReadNormal WrittenDictionary impossible
notWritten FamilyReadNormal WrittenShape impossible
notWritten FormReadNormal WrittenDictionary impossible
notWritten FormReadNormal WrittenShape impossible

-- A form of such a kind is the host's normal form of its term, contracted.
0 normalOnly : ReadOffNormal k -> FormFrom k ctx t u -> (r : NormalReading OfNormaliseTypes ctx t ** u = r.readForm)
normalOnly _ (FromNormalForm r) = (r ** Refl)
normalOnly nk (FromWritten wk _) = void (notWritten nk wk)
normalOnly TypeReadNormal (FromImplementation _) impossible
normalOnly FamilyReadNormal (FromImplementation _) impossible
normalOnly FormReadNormal (FromImplementation _) impossible

-- The induction at the root, at a form read off the host's normal form.
0 formCovers : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {ctx : Frozen} -> {ns : Scope} ->
               {bs : Bounds ns} -> {vs : SubstEnv ns []} -> ReadOffNormal k ->
               NodeCovers m s (evaluationOf OfNormaliseTypes) ctx bs vs u t ->
               FormFrom k ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs u) form -> EtaNormal EveryRedex form ->
               (r : Template) -> ReadAs (InstanceMode ctx) [] form r -> Writes m s t r
formCovers nk covers from maximal r read = case normalOnly nk from of
  (nr ** Refl) => covers nr.reduct.steps nr.reduct.normal nr.contraction maximal r read

||| The reading lemma at the root, from its induction (`NodeCovers`), for
||| a kind read off the host's normal form: the instance's form is that
||| normal form of the site's term with the values put in, contracted, and
||| it holds no redex (`Readings.InstanceReading`'s `maximal`), so the
||| induction's premises are the instance reading's own. A dictionary and
||| a shape a constructor heads are read as written, which no normal form
||| relates to the site's: theirs is a separate obligation.
export
0 coversAtRoot : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {ctx : Frozen} -> {ns : Scope} ->
                 {bs : Bounds ns} -> {vs : SubstEnv ns []} -> ReadOffNormal k ->
                 NodeCovers m s (evaluationOf OfNormaliseTypes) ctx bs vs u t ->
                 (inst : InstanceReading ctx k (putIn SizeOf.zero (mkSizeOf ns) bs vs u)) -> Writes m s t inst.template
coversAtRoot nk covers inst = formCovers nk covers inst.formFrom inst.maximal inst.template inst.describes

||| What an instance writes under a site's reading, the template written at
||| a node, it writes under the template the graph's site holds, that
||| reading read where the node's families land: the site reaches its own
||| template (`closedWrites`).
export
0 landedWrites : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {c : Nat -> Landing} -> LandingsWrite m s c ->
                 s.template = withClosedFamilies c t -> Writes m s t w -> Writes m s s.template w
landedWrites ls same wr =
  rewrite same in closedWrites ls (replace {p = \x => Reaches x (withClosedFamilies c t)} (sym same) ReachesItself) wr

||| What a site of the model writes at a request's argument, of any kind,
||| from the reading lemma at the site the request read: the graph's site
||| holds the template the argument was written as read where its writer's
||| families land (`Graph.SiteLanding`), which is its reading's template as
||| the target is given it (`Sites.writtenReading`), and the lemma gives what it
||| writes at the instance's reading of the argument, which giving it to
||| the target (`asGivenWrites`) and that reading keep (`landedWrites`).
export
0 siteWritesRead : {g : Graph} -> {m : Model g} -> {p : Fin g.size} -> {c : Nat -> Landing} -> (s : SiteOf m p) ->
                   (r : SiteReading k t) -> (given : Maybe ChoiceHead) -> (root : Root) -> LandingsWrite m s.site c ->
                   s.site.template = withClosedFamilies c (asGiven given (r.template, root)) ->
                   ReadingCovers m s.site stands k t r ->
                   (mk : Markers r.mode.inContext ns) -> (vs : SubstEnv ns []) ->
                   MarkersHold m s.site r.mode.inContext stands mk.bounds vs ->
                   (inst : InstanceReading r.mode.inContext k (putIn SizeOf.zero (mkSizeOf ns) mk.bounds vs t)) ->
                   SiteWrites m p inst.template
siteWritesRead s r given root ls same covers mk vs held inst =
  siteWritten s (landedWrites ls same (asGivenWrites given root (covers mk vs held inst)))

------------------------------------------------------------------------------
-- Templates that name nothing
------------------------------------------------------------------------------

mutual
  ||| A template that names no parameter, choice, member, field or
  ||| recursion: heads over such templates, leaves, tokens and arguments of
  ||| a family's value. What an instance writes where a site's template is
  ||| one is that template (`plainWrites`).
  public export
  data Plain : Template -> Type where
    PlainHead : AllPlain ts -> Plain (Head a ts)
    PlainLeaf : Plain (Leaf h)
    PlainToken : Plain (Token k)
    PlainFormal : Plain (Formal j k)

  public export
  data AllPlain : List Template -> Type where
    NonePlain : AllPlain []
    EachPlain : Plain t -> AllPlain ts -> AllPlain (t :: ts)

mutual
  ||| A template that names nothing writes itself.
  export
  0 plainWrites : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> Plain t -> Writes m s t t
  plainWrites (PlainHead ps) = AtHead (allPlainWrite ps)
  plainWrites PlainLeaf = AtLeaf
  plainWrites PlainToken = AtToken
  plainWrites PlainFormal = AtFormal

  0 allPlainWrite : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> AllPlain ts -> AllWrite m s ts ts
  allPlainWrite NonePlain = []
  allPlainWrite (EachPlain p ps) = plainWrites p :: allPlainWrite ps

-- A spelt constant's leaves name nothing.
0 speltPlain : (cs : List Char) -> AllPlain (spelt cs ++ [])
speltPlain [] = NonePlain
speltPlain (_ :: cs) = EachPlain PlainLeaf (speltPlain cs)

||| What an instance reads a constant as names nothing.
export
0 constantPlain : (c : Constant) -> Plain (constantRead c)
constantPlain (I _) = PlainToken
constantPlain (I8 _) = PlainToken
constantPlain (I16 _) = PlainToken
constantPlain (I32 _) = PlainToken
constantPlain (I64 _) = PlainToken
constantPlain (BI _) = PlainToken
constantPlain (B8 _) = PlainToken
constantPlain (B16 _) = PlainToken
constantPlain (B32 _) = PlainToken
constantPlain (B64 _) = PlainToken
constantPlain (Str x) = PlainHead (speltPlain (unpack x))
constantPlain (Db x) = PlainHead (speltPlain (unpack (show x)))
constantPlain (Ch _) = PlainLeaf
constantPlain (PrT _) = PlainLeaf
constantPlain WorldVal = PlainLeaf

------------------------------------------------------------------------------
-- The host's location-only steps
------------------------------------------------------------------------------

-- A constant and a universe head no spine of a reference or an unknown:
-- each is a node of its own.
0 constantNotRef : Spine (PrimVal fc c) (Ref rfc nt n) args -> Void
constantNotRef Host.Head impossible
constantNotRef (Host.Applied _) impossible

0 constantNotMeta : Spine (PrimVal fc c) (Meta mfc y i scope) more -> Void
constantNotMeta Host.Head impossible
constantNotMeta (Host.Applied _) impossible

0 universeNotRef : Spine (TType fc u) (Ref rfc nt n) args -> Void
universeNotRef Host.Head impossible
universeNotRef (Host.Applied _) impossible

0 universeNotMeta : Spine (TType fc u) (Meta mfc y i scope) more -> Void
universeNotMeta Host.Head impossible
universeNotMeta (Host.Applied _) impossible

-- No step of the evaluator applies at a constant or a universe alone:
-- each step's left side is a node of another form, or a reference or an
-- unknown at the head of its spine.
0 constantNoStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Contracts ev ctx (PrimVal fc c) v -> Void
constantNoStep (Unfold s _ _ _ _ _ _ _) = constantNotRef s
constantNoStep (Solve s _ _ _ _ _ _ _ _) = constantNotMeta s
constantNoStep (Primitive s _ _ _ _ _) = constantNotRef s

0 universeNoStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Contracts ev ctx (TType fc u) v -> Void
universeNoStep (Unfold s _ _ _ _ _ _ _) = universeNotRef s
universeNoStep (Solve s _ _ _ _ _ _ _ _) = universeNotMeta s
universeNoStep (Primitive s _ _ _ _ _) = universeNotRef s

||| What a constant reduces to: itself, at some location. The host's steps
||| are blind to locations, and every node they rebuild may take a new one.
export
0 constantReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Reduces ev ctx (PrimVal fc c) v -> (fc' : FC ** v = PrimVal fc' c)
constantReduces (Then r r') = case constantReduces r of
  (_ ** Refl) => constantReduces r'
constantReduces (Contract st) = void (constantNoStep st)
constantReduces APrimVal = (_ ** Refl)

||| What a universe reduces to: itself, at some location.
export
0 universeReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Reduces ev ctx (TType fc u) v -> (fc' : FC ** v = TType fc' u)
universeReduces (Then r r') = case universeReduces r of
  (_ ** Refl) => universeReduces r'
universeReduces (Contract st) = void (universeNoStep st)
universeReduces AType = (_ ** Refl)

-- Contraction rewrites no constant, universe or erased part no dot holds.
0 constantKept : EtaContracts (PrimVal fc c) v -> v = PrimVal fc c
constantKept EtaSame = Refl

0 universeKept : EtaContracts (TType fc u) v -> v = TType fc u
universeKept EtaSame = Refl

0 erasedKept : Undotted why -> EtaContracts (Erased fc why) v -> v = Erased fc why
erasedKept _ EtaSame = Refl
erasedKept IsPlaceholder (EtaDotted _) impossible
erasedKept IsImpossible (EtaDotted _) impossible

-- Putting values in keeps a constant, a universe and an erased part no
-- dot holds: `substTerm` and `mkLocals` rebuild each as it is.
0 putInConstant : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (env : SubstEnv ns vars) ->
                  putIn o sz bs env (PrimVal fc c) = PrimVal fc c
putInConstant o sz None env = Refl
putInConstant o sz (Add new old rest) env = Refl

0 putInUniverse : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (env : SubstEnv ns vars) ->
                  putIn o sz bs env (TType fc u) = TType fc u
putInUniverse o sz None env = Refl
putInUniverse o sz (Add new old rest) env = Refl

0 putInErased : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (env : SubstEnv ns vars) -> Undotted why ->
                putIn o sz bs env (Erased fc why) = Erased fc why
putInErased o sz None env IsPlaceholder = Refl
putInErased o sz None env IsImpossible = Refl
putInErased o sz (Add new old rest) env IsPlaceholder = Refl
putInErased o sz (Add new old rest) env IsImpossible = Refl

0 runNotUniverse : Run (TType fc u) k -> Void
runNotUniverse Literals.RunZero impossible
runNotUniverse (RunSucc _) impossible

0 runNotErased : Run (Erased fc why) k -> Void
runNotErased Literals.RunZero impossible
runNotErased (RunSucc _) impossible

-- What an instance reads a universe and an erased part no dot holds as:
-- one leaf.
0 universeReadAs : ReadAs (InstanceMode ctx) env (TType fc u) r -> r = Leaf 1
universeReadAs (ASpine (SUniverse [])) = Refl
universeReadAs (ARun run) = void (runNotUniverse run)

0 erasedReadAs : Undotted why -> ReadAs (InstanceMode ctx) env (Erased fc why) r -> r = Leaf 1
erasedReadAs IsPlaceholder (ASpine (SPlaceholder [])) = Refl
erasedReadAs IsImpossible (ASpine (SImpossible [])) = Refl
erasedReadAs _ (ARun run) = void (runNotErased run)

||| The induction at a constant applied to nothing: the host's steps only
||| move it (`constantReduces`), contraction keeps it, and the instance
||| reads it as the site does, a template that names nothing, which writes
||| itself.
export
0 atConstant : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
               {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} -> {0 w, v : ClosedTerm} ->
               Reduces ev ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs (PrimVal fc c)) w -> Irreducible ev ctx w ->
               EtaContracts w v -> EtaNormal EveryRedex v -> (r : Template) -> ReadAs (InstanceMode ctx) [] v r ->
               Writes m s (constantRead c) r
atConstant {ns} {bs} {vs} {w} steps normal contracted maximal r read =
  case constantReduces (replace {p = \x => Reduces ev ctx x w} (putInConstant SizeOf.zero (mkSizeOf ns) bs vs) steps) of
    (_ ** Refl) => case constantKept contracted of
      Refl => case constantReadAs read of
        Refl => plainWrites (constantPlain c)

||| The induction at a universe applied to nothing, read as one leaf by the
||| site and by every instance: the host's steps only move it.
export
0 atUniverse : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
               {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} -> {0 w, v : ClosedTerm} ->
               Reduces ev ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs (TType fc u)) w -> Irreducible ev ctx w ->
               EtaContracts w v -> EtaNormal EveryRedex v -> (r : Template) -> ReadAs (InstanceMode ctx) [] v r ->
               Writes m s (Leaf 1) r
atUniverse {ns} {bs} {vs} {w} steps normal contracted maximal r read =
  case universeReduces (replace {p = \x => Reduces ev ctx x w} (putInUniverse SizeOf.zero (mkSizeOf ns) bs vs) steps) of
    (_ ** Refl) => case universeKept contracted of
      Refl => case universeReadAs read of
        Refl => AtLeaf

||| The induction at a placeholder or what is impossible, applied to
||| nothing, read as one leaf by the site and by every instance: the
||| host's steps only move it (`Proof.Inversion.erasedReduces`).
export
0 atErased : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
             {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} -> Undotted why -> {0 w, v : ClosedTerm} ->
             Reduces ev ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs (Erased fc why)) w -> Irreducible ev ctx w ->
             EtaContracts w v -> EtaNormal EveryRedex v -> (r : Template) -> ReadAs (InstanceMode ctx) [] v r ->
             Writes m s (Leaf 1) r
atErased {ns} {bs} {vs} {w} undotted steps normal contracted maximal r read =
  case erasedReduces undotted (replace {p = \x => Reduces ev ctx x w} (putInErased SizeOf.zero (mkSizeOf ns) bs vs undotted) steps) of
    (_ ** Refl) => case erasedKept undotted contracted of
      Refl => case erasedReadAs undotted read of
        Refl => AtLeaf

------------------------------------------------------------------------------
-- A closed run and a data constructor
------------------------------------------------------------------------------

||| Putting values in keeps a closed run: its heads are constructors, which
||| no value is put in for (`Proof.Inversion.putInHead`).
export
0 putInRun : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (env : SubstEnv ns vars) -> Run u k ->
             putIn o sz bs env u = u
putInRun o sz bs env Literals.RunZero = putInHead o sz bs env KeptData
putInRun o sz bs env (RunSucc {fc} {rfc} {tag} {arity} {s} {a} run) =
  trans (putInApp {fc} o sz bs env (Ref rfc (DataCon tag arity) s) a)
        (cong2 (App fc) (putInHead o sz bs env KeptData) (putInRun o sz bs env run))

||| A closed run reduces only to a run as long: its constructors are inert
||| (`Proof.Inversion.inertAlone`, `Proof.Inversion.inertOne`).
export
0 runReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Run u k -> Reduces ev ctx u w -> Run w k
runReduces Literals.RunZero r = case inertAlone InertData r of
  (_ ** Refl) => Literals.RunZero
runReduces (RunSucc run) r = case inertOne InertData r of
  (_ ** _ ** _ ** (Refl, ra)) => RunSucc (runReduces run ra)

-- Contraction rewrites no reference.
0 refKept : EtaContracts (Ref fc nt n) v -> v = Ref fc nt n
refKept EtaSame = Refl

||| Contraction keeps a closed run: it holds no lambda.
export
0 runContracted : Run v k -> EtaContracts v v' -> v' = v
runContracted _ EtaSame = Refl
runContracted (RunSucc run) (EtaApp cf ca) = rewrite refKept cf in rewrite runContracted run ca in Refl

||| The induction at a closed run the site reads as its leaf: putting
||| values in keeps it (`putInRun`), the host's steps reduce only under its
||| constructors to a run as long (`runReduces`), contraction keeps it
||| (`runContracted`), and an instance reads that run as its leaf or node
||| by node (`runRead`), either of which the leaf writes (`AtRunRead`).
export
0 runCovers : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
              {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} -> Run u k -> {0 w, v : ClosedTerm} ->
              Reduces ev ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs u) w -> Irreducible ev ctx w ->
              EtaContracts w v -> EtaNormal EveryRedex v -> (r : Template) -> ReadAs (InstanceMode ctx) [] v r ->
              Writes m s (Leaf (S k)) r
runCovers {ns} {bs} {vs} {w} {v} run steps normal contracted maximal r read =
  let reduced = runReduces run (replace {p = \x => Reduces ev ctx x w} (putInRun SizeOf.zero (mkSizeOf ns) bs vs run) steps) in
  AtRunRead (runRead (replace {p = \x => Run x k} (sym (runContracted reduced contracted)) reduced) read)

------------------------------------------------------------------------------
-- Heads the host rewrites by their shape
------------------------------------------------------------------------------

0 tyConNotFunc : the (Term vs) (Ref fc (TyCon k) n) = Ref fc' Func n' -> Void
tyConNotFunc Refl impossible

||| A step at a type constructor of no arguments is the one its name takes
||| where it names a type, wherever the node is: the host's steps are blind
||| to locations, and a function or an unknown heads no such node.
export
0 namedTypeStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Contracts ev ctx (Ref fc (TyCon Z) n) v -> NamedType n
namedTypeStep (TypeName root) = NamesUniverse root
namedTypeStep (ConstantTypeName named) = NamesPrimitive named
namedTypeStep (Unfold s _ _ _ _ _ _ _) = void (tyConNotFunc (fst (refSpines Host.Head s)))
namedTypeStep (Solve s _ _ _ _ _ _ _ _) = void (refNotMeta Host.Head s)
namedTypeStep (Primitive s _ _ _ _ _) = void (tyConNotFunc (fst (refSpines Host.Head s)))

||| What a type constructor of no arguments whose name names no type
||| reduces to: itself, at some location, since a step there, at whatever
||| location the node has moved to, is one its name takes (`namedTypeStep`).
export
0 unnamedTypeReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Not (NamedType n) ->
                       Reduces ev ctx (Ref fc (TyCon Z) n) w -> (fc' : FC ** w = Ref fc' (TyCon Z) n)
unnamedTypeReduces none (Then r r') = case unnamedTypeReduces none r of
  (_ ** Refl) => unnamedTypeReduces none r'
unnamedTypeReduces none (Contract st) = void (none (namedTypeStep st))
unnamedTypeReduces none ARef = (_ ** Refl)

||| The induction at a type constructor of no arguments, where the site's
||| form takes no step a node's shape decides there, as a form read off
||| the host's normal form takes none anywhere
||| (`Proof.Reading.readNoShapeStep`): its name names no type, putting
||| values in keeps it, the host's steps only move it
||| (`unnamedTypeReduces`), contraction keeps it, and the instance reads it
||| as the site does, by the address the context gives it.
export
0 atNamedType : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
                {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
                Not (ShapeRedex ev (Ref fc (TyCon Z) n)) -> (0 at : AddressedAs (InstanceMode ctx) n a) ->
                {0 w, v : ClosedTerm} ->
                Reduces ev ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs (Ref fc (TyCon Z) n)) w -> Irreducible ev ctx w ->
                EtaContracts w v -> EtaNormal EveryRedex v -> (r : Template) -> ReadAs (InstanceMode ctx) [] v r ->
                Writes m s (Head a []) r
atNamedType {ns} {bs} {vs} {w} normalHere at steps normal contracted maximal r read =
  case unnamedTypeReduces (\named => normalHere (ShapeAtName named))
         (replace {p = \x => Reduces ev ctx x w} (putInHead SizeOf.zero (mkSizeOf ns) bs vs KeptFamily) steps) of
    (_ ** Refl) => case refKept contracted of
      Refl => case familyRead Host.Head read of
        (a' ** [] ** (Refl, at', [])) => case trans (sym at') at of
          Refl => AtHead []

||| A head applied to its spine's arguments, where its application is a
||| step a node's shape decides: the head alone, or a term that takes that
||| step at the innermost application.
export
0 appliedShape : Spine u h args -> AppliedHead h -> Either (u = h) (ShapeRedex ev u)
appliedShape Host.Head _ = Left Refl
appliedShape {ev} (Host.Applied s) h = case appliedShape {ev} s h of
  Left Refl => Right (ShapeAtApplied h)
  Right r => Right (ShapeInFunction r)

||| A head that drops what it is applied to heads a node of a form that
||| takes no step a node's shape decides alone: a constant, a universe, a
||| placeholder, what is impossible and a delay are each met by the
||| induction applied to nothing (`atConstant`, `atUniverse`, `atErased`),
||| never applied, which the host would drop (`DropApplied`) though the
||| site reads every argument.
export
0 dropsAlone : Spine u f args -> DropsArguments f -> Not (ShapeRedex ev u) -> u = f
dropsAlone {ev} s dropped normalHere = case appliedShape {ev} s (DropsApplied dropped) of
  Left same => same
  Right r => void (normalHere r)

||| A `let` is no node of a form, read off the host's normal form, of an
||| evaluation that runs everything: it would take a step there (`Zeta`),
||| so the induction never meets one where the instance's evaluation would
||| run it.
export
0 noLetWhereRun : (0 _ : ev.running = RunsAll) -> Not (ShapeRedex ev (Bind fc x (Let lfc c val ty) sc)) -> Void
noLetWhereRun runs normalHere = normalHere (ShapeAtLet runs)

||| The induction's hypothesis at each argument of a node: each writes
||| what the site's reading reads it as (`NodeCovers`).
public export
data AllNodeCovers : {g : Graph} -> Model g -> Bound.Site g.size -> Evaluation -> Frozen -> Bounds ns -> SubstEnv ns [] ->
                     List ClosedTerm -> List Template -> Type where
  NoneCovers : AllNodeCovers m s ev ctx bs vs [] []
  EachCovers : NodeCovers m s ev ctx bs vs a t -> AllNodeCovers m s ev ctx bs vs as ts ->
               AllNodeCovers m s ev ctx bs vs (a :: as) (t :: ts)

-- What each argument of a node writes, by the induction at each.
0 coversAll : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
              {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
              AllNodeCovers m s ev ctx bs vs args ts -> AllReduce ev ctx (map (putIn SizeOf.zero (mkSizeOf ns) bs vs) args) ws ->
              All (Irreducible ev ctx) ws -> AllContract ws us -> All (EtaNormal EveryRedex) us ->
              AllReadAs (InstanceMode ctx) [] us outs -> AllWrite m s ts outs
coversAll NoneCovers NoneLeft [] NoneContracted [] [] = []
coversAll (EachCovers covers rest) (Each red reds) (irr :: irrs) (EachContracted ck cks) (nm :: nms) (x :: xs) =
  covers red irr ck nm _ x :: coversAll rest reds irrs cks nms xs

-- A closed run's spine has one argument at most.
0 longRun : Run v k -> Spine v h (x :: y :: zs) -> Void
longRun Literals.RunZero Host.Head impossible
longRun Literals.RunZero (Host.Applied _) impossible
longRun (RunSucc _) Host.Head impossible
longRun (RunSucc _) (Host.Applied Host.Head) impossible
longRun (RunSucc _) (Host.Applied (Host.Applied _)) impossible

-- A closed run where the site reads a data constructor node by node: of
-- no argument, its zero, which the node, one high, cuts to (`AtCut`); of
-- one, a successor over a run one shorter, which its argument writes, by
-- the induction there (`AtRun`); of more, none (`longRun`).
0 runAtConstructor : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
                     {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
                     AllNodeCovers m s ev ctx bs vs args ts -> AllReduce ev ctx (map (putIn SizeOf.zero (mkSizeOf ns) bs vs) args) ws ->
                     All (Irreducible ev ctx) ws -> AllContract ws us -> Spine v (Ref fc (DataCon tag arity) n) us ->
                     EtaNormal EveryRedex v -> Run v k -> Writes m s (Head a ts) (Leaf (S k))
runAtConstructor NoneCovers NoneLeft [] NoneContracted sv _ run = case headOnly sv Refl of
  Refl => case run of
    Literals.RunZero => AtCut (AtHead []) (LTESucc LTEZero)
runAtConstructor (EachCovers covers NoneCovers) (Each red NoneLeft) [irr] (EachContracted ck NoneContracted) sv maximal run =
  case oneApplied sv Refl of
    (_ ** Refl) => case maximal of
      NormalApp _ nm => case run of
        RunSucc run' => AtRun (covers red irr ck nm _ (ARun run')) RunLeaf
runAtConstructor (EachCovers _ (EachCovers _ _)) (Each _ (Each _ _)) (_ :: _ :: _) (EachContracted _ (EachContracted _ _)) sv _ run =
  void (longRun run sv)

||| The induction at a data constructor the site reads node by node, over
||| the induction at each argument: the instance's term reduces under the
||| constructor, each argument normal, contracted with no redex left
||| (`spineNormal`) and read (`atConstructor`'s inversion). Where the
||| instance reads it node by node, it writes the constructor over what each
||| argument writes; where it reads a closed run's leaf, the site's
||| successor over a run one shorter (`AtRun`), or its zero, cut to the one
||| leaf a run's zero is (`AtCut`).
export
0 dataCovers : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
               {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
               Spine u (Ref fc (DataCon tag arity) n) args -> (0 at : AddressedAs (InstanceMode ctx) n a) ->
               AllNodeCovers m s ev ctx bs vs args ts -> {0 w, v : ClosedTerm} ->
               Reduces ev ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs u) w -> Irreducible ev ctx w ->
               EtaContracts w v -> EtaNormal EveryRedex v -> (r : Template) -> ReadAs (InstanceMode ctx) [] v r ->
               Writes m s (Head a ts) r
dataCovers {ns} {bs} {vs} sp at covers steps normal contracted maximal r read =
  case inertPutIn SizeOf.zero (mkSizeOf ns) bs vs InertData KeptData sp steps of
    ReducedUnder sw rs => case refContracts sw contracted of
      ContractedUnder sv cs => case read of
        ARun run => runAtConstructor covers rs (argumentsIrreducible sw normal) cs sv maximal run
        ASpine spread => case dataSpine (spineRead sv spread) of
          (a' ** ts' ** (Refl, at', reads)) => case trans (sym at') at of
            Refl => AtHead (coversAll covers rs (argumentsIrreducible sw normal) cs (spineNormal sv maximal)
                              (replace {p = \zs => AllReadAs (InstanceMode ctx) [] zs ts'} (appendNilRightNeutral _) reads))

------------------------------------------------------------------------------
-- A function the context gives no address
------------------------------------------------------------------------------

0 runNotFunc : Run u k -> Spine u (Ref fc Func n) args -> Void
runNotFunc Literals.RunZero Host.Head impossible
runNotFunc Literals.RunZero (Host.Applied _) impossible
runNotFunc (RunSucc _) Host.Head impossible
runNotFunc (RunSucc _) (Host.Applied Host.Head) impossible
runNotFunc (RunSucc _) (Host.Applied (Host.Applied _)) impossible

-- An instance reads a function its context gives no address as a part
-- over its arguments' readings; one the context gives an address it reads
-- as the call, which the two addresses rule out.
0 undefinedSpine : AddressedAs (InstanceMode ctx) n Nothing -> SpineAs (InstanceMode ctx) env (Ref fc Func n) as r ->
                   (ts : List Template ** (r = partOf EveryNode (Leaf 1) ts, AllReadAs (InstanceMode ctx) env as ts))
undefinedSpine none (SNoDefinition _ rs) = (_ ** (Refl, rs))
undefinedSpine none (SKept at _) = void (nothingNotJust (trans (sym none) at))

||| An instance's reading of a term a function its context gives no
||| address heads: a part over its arguments' readings, never a closed
||| run's leaf.
export
0 undefinedRead : AddressedAs (InstanceMode ctx) n Nothing -> Spine u (Ref fc Func n) args -> ReadAs (InstanceMode ctx) env u r ->
                  (ts : List Template ** (r = partOf EveryNode (Leaf 1) ts, AllReadAs (InstanceMode ctx) env args ts))
undefinedRead none s (ARun run) = void (runNotFunc run s)
undefinedRead {args} none s (ASpine sp) = case undefinedSpine none (spineRead s sp) of
  (ts ** (same, rs)) => (ts ** (same, replace {p = \zs => AllReadAs (InstanceMode ctx) env zs ts} (appendNilRightNeutral args) rs))

-- A part over what each argument writes writes the part over what each
-- argument's reading reads.
0 partWrites : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} ->
               AllWrite m s ts ws -> Writes m s (partOf EveryNode (Leaf 1) ts) (partOf EveryNode (Leaf 1) ws)
partWrites [] = AtLeaf
partWrites (w :: rest) = AtHead (AtLeaf :: w :: rest)

||| The induction at a function the context defines as nothing, applied,
||| in a form that keeps every node: putting values in keeps the function,
||| the host's steps reduce only its arguments
||| (`Proof.Inversion.InertUndefined`), contraction keeps it, and the
||| instance reads it as the site does, a part over what each argument
||| writes, by the induction at each.
export
0 undefinedCovers : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {0 ev : Evaluation} -> {ctx : Frozen} ->
                    {ns : Scope} -> {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
                    (0 none : (d : GlobalDef) -> Not (Defines ctx n d)) -> (0 at : AddressedAs (InstanceMode ctx) n Nothing) ->
                    Spine u (Ref fc Func n) args -> AllNodeCovers m s ev ctx bs vs args ts -> {0 w, v : ClosedTerm} ->
                    Reduces ev ctx (putIn SizeOf.zero (mkSizeOf ns) bs vs u) w -> Irreducible ev ctx w ->
                    EtaContracts w v -> EtaNormal EveryRedex v -> (r : Template) -> ReadAs (InstanceMode ctx) [] v r ->
                    Writes m s (partOf EveryNode (Leaf 1) ts) r
undefinedCovers {ns} {bs} {vs} none at sp covers steps normal contracted maximal r read =
  case inertPutIn SizeOf.zero (mkSizeOf ns) bs vs (InertUndefined none) KeptFunc sp steps of
    ReducedUnder sw rs => case refContracts sw contracted of
      ContractedUnder sv cs => case undefinedRead at sv read of
        (outs ** (Refl, reads)) =>
          partWrites (coversAll covers rs (argumentsIrreducible sw normal) cs (spineNormal sv maximal) reads)

||| That every name a frozen context defines has an address: what the
||| induction needs where a site's term holds a function the context gives
||| none (`undefinedCovers`). It is the host's fact: the frozen entries are
||| read from entry 0 up, so a defined name resolves to a non-negative
||| entry, which `Walk.placementIn` places. No module states it yet; this
||| is its statement, which `Idris.Host` is to prove.
public export
0 PlacedWhereDefined : Frozen -> Type
PlacedWhereDefined ctx = {0 n : Name} -> {0 d : GlobalDef} -> Defines ctx n d -> (a : Address ** AddressedAs (InstanceMode ctx) n (Just a))

||| A name the context gives no address it defines as nothing, wherever
||| every name it defines has an address.
export
0 unaddressedUndefined : PlacedWhereDefined ctx -> AddressedAs (InstanceMode ctx) n Nothing ->
                         (d : GlobalDef) -> Not (Defines ctx n d)
unaddressedUndefined placed none d defines = case placed defines of
  (a ** addressed) => nothingNotJust (trans (sym none) addressed)

------------------------------------------------------------------------------
-- Binders, inverted
------------------------------------------------------------------------------

-- What an implicitness reduces to, then to again.
0 piThen : {0 ev : Evaluation} -> {0 ctx : Frozen} -> PiReduces ev ctx p p' -> PiReduces ev ctx p' p'' -> PiReduces ev ctx p p''
piThen AnImplicit AnImplicit = AnImplicit
piThen AnExplicit AnExplicit = AnExplicit
piThen AnAutoImplicit AnAutoImplicit = AnAutoImplicit
piThen (ADefImplicit r) (ADefImplicit r') = ADefImplicit (Then r r')

-- A binder heads no spine of a reference or an unknown.
0 bindNotRef : Spine (Bind fc x b sc) (Ref rfc nt n) args -> Void
bindNotRef Host.Head impossible
bindNotRef (Host.Applied _) impossible

0 bindNotMeta : Spine (Bind fc x b sc) (Meta mfc y i scope) more -> Void
bindNotMeta Host.Head impossible
bindNotMeta (Host.Applied _) impossible

-- No step of the evaluator applies at a lambda or a function type alone:
-- beta and the floats apply only where one is applied, `Zeta` only at a
-- `let`, and every other step at a reference or an unknown.
0 lambdaNoStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Contracts ev ctx (Bind fc x (Lam lfc c p ty) sc) v -> Void
lambdaNoStep (Unfold s _ _ _ _ _ _ _) = bindNotRef s
lambdaNoStep (Solve s _ _ _ _ _ _ _ _) = bindNotMeta s
lambdaNoStep (Primitive s _ _ _ _ _) = bindNotRef s

0 piNoStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Contracts ev ctx (Bind fc x (Pi pfc c p ty) sc) v -> Void
piNoStep (Unfold s _ _ _ _ _ _ _) = bindNotRef s
piNoStep (Solve s _ _ _ _ _ _ _ _) = bindNotMeta s
piNoStep (Primitive s _ _ _ _ _) = bindNotRef s

||| What a lambda alone reduces to: a lambda, at some location, over what
||| its implicitness, its type and its body reduce to, since no step
||| applies at its root (`lambdaNoStep`). The first half of the inversion
||| at a binder; the induction under it is the reading lemma's open
||| obligation.
export
0 lambdaReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Reduces ev ctx (Bind fc x (Lam lfc c p ty) sc) w ->
                  (fc' : FC ** lfc' : FC ** p' : PiInfo (Term vs) ** ty' : Term vs ** sc' : Term (x :: vs) **
                    (w = Bind fc' x (Lam lfc' c p' ty') sc', PiReduces ev ctx p p', Reduces ev ctx ty ty', Reduces ev ctx sc sc'))
lambdaReduces (Then r r') = case lambdaReduces r of
  (_ ** _ ** _ ** _ ** _ ** (Refl, pr, tr, sr)) => case lambdaReduces r' of
    (fc' ** lfc' ** p'' ** ty'' ** sc'' ** (same, pr', tr', sr')) =>
      (fc' ** lfc' ** p'' ** ty'' ** sc'' ** (same, piThen pr pr', Then tr tr', Then sr sr'))
lambdaReduces (Contract st) = void (lambdaNoStep st)
lambdaReduces (ABind (ALam pr tr) sr) = (_ ** _ ** _ ** _ ** _ ** (Refl, pr, tr, sr))

||| What a function type alone reduces to: a function type, at some
||| location, over what its implicitness, its domain and its codomain
||| reduce to (`piNoStep`).
export
0 piReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Reduces ev ctx (Bind fc x (Pi pfc c p ty) sc) w ->
              (fc' : FC ** pfc' : FC ** p' : PiInfo (Term vs) ** ty' : Term vs ** sc' : Term (x :: vs) **
                (w = Bind fc' x (Pi pfc' c p' ty') sc', PiReduces ev ctx p p', Reduces ev ctx ty ty', Reduces ev ctx sc sc'))
piReduces (Then r r') = case piReduces r of
  (_ ** _ ** _ ** _ ** _ ** (Refl, pr, tr, sr)) => case piReduces r' of
    (fc' ** pfc' ** p'' ** ty'' ** sc'' ** (same, pr', tr', sr')) =>
      (fc' ** pfc' ** p'' ** ty'' ** sc'' ** (same, piThen pr pr', Then tr tr', Then sr sr'))
piReduces (Contract st) = void (piNoStep st)
piReduces (ABind (APi pr tr) sr) = (_ ** _ ** _ ** _ ** _ ** (Refl, pr, tr, sr))
