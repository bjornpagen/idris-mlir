-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The parts the reading lemma (`Frontend.Growth.Template.ReadingCovers`)
||| is built from, each over the readers' relation (`ReadAs`) and the host's
||| (`Idris.Host.Reduces`):
|||
||| - at a node of the site's term an inert head heads, what an instance
|||   reads: the head over what each argument, the instance's values put
|||   in, reaches as a normal form, contracted and read (`atConstructor`,
|||   `familyRead`, `boundRead`), or a closed run's leaf;
||| - a match on a marker binding each field to a marker of its own: the
|||   instance's value for that marker is the field, which the markers then
|||   hold too (`fieldMarkerHolds`), since any reading of the field is a
|||   child of a reading of the constructor applied (`readsAny`);
||| - a builtin read beside its call: the constant the host computes at an
|||   instance measures within one computation's growth of what its
|||   arguments measure (`computedMeasured`), the premise of
|||   `Proof.Bound.AtComputed`;
||| - the graph's rewrites of a site's template: what an instance writes
|||   under the reading, it writes under the template the graph keeps
|||   (`asGivenWrites`, `closedWrites`);
||| - two readings of one term as an instance's are one reading but for an
|||   argument's number and a run read as its leaf (`readsAlike`), so a
|||   request's argument, which a site wrote, holds the requested
|||   instance's markers (`requestHolds`).
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Covers

import Core.Context
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Derivation
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Inversion
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
runNotFamily Keys.RunZero Host.Head impossible
runNotFamily Keys.RunZero (Host.Applied _) impossible
runNotFamily (RunSucc _) Host.Head impossible
runNotFamily (RunSucc _) (Host.Applied Host.Head) impossible
runNotFamily (RunSucc _) (Host.Applied (Host.Applied _)) impossible

0 runNotBound : Run u k -> Spine u (Ref fc Bound n) args -> Void
runNotBound Keys.RunZero Host.Head impossible
runNotBound Keys.RunZero (Host.Applied _) impossible
runNotBound (RunSucc _) Host.Head impossible
runNotBound (RunSucc _) (Host.Applied Host.Head) impossible
runNotBound (RunSucc _) (Host.Applied (Host.Applied _)) impossible

0 runNotConstant : Run (PrimVal fc c) k -> Void
runNotConstant Keys.RunZero impossible
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
  HoleRead : (0 _ : Closed.markerOf n = Just i) -> BoundRead n ts (partOf EveryNode (Token (S i)) ts)
  FormalRead : (0 _ : probeOf n = Just (ProbeFormal j k)) -> BoundRead n ts (partOf EveryNode (Formal j k) ts)
  PartRead : (0 _ : Closed.markerOf n = Nothing) -> (0 _ : NotFormal n) -> BoundRead n ts (partOf EveryNode (Leaf 1) ts)

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
||| argument, values put in, reduces to, contracted, and read.
public export
data ArgumentsRead : Evaluation -> Frozen -> List ClosedTerm -> List Template -> Type where
  NoneRead : ArgumentsRead ev ctx [] []
  EachRead : Reduces ev ctx a w -> Irreducible ev ctx w -> EtaContracts w u -> ReadAs (InstanceMode ctx) [] u t ->
             ArgumentsRead ev ctx as ts -> ArgumentsRead ev ctx (a :: as) (t :: ts)

0 argumentsRead : {0 ev : Evaluation} -> AllReduce ev ctx as ws -> All (Irreducible ev ctx) ws -> AllContract ws us ->
                  AllReadAs (InstanceMode ctx) [] us ts -> ArgumentsRead ev ctx as ts
argumentsRead NoneLeft [] NoneContracted [] = NoneRead
argumentsRead (Each r rs) (n :: ns) (EachContracted c cs) (x :: xs) = EachRead r n c x (argumentsRead rs ns cs xs)

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
                  ReadAs (InstanceMode ctx) [] v r -> AtConstructor ev ctx n (map (putIn SizeOf.zero sz bs vs) args) r
atConstructor sz bs vs s steps normal contracted read = case inertPutIn SizeOf.zero sz bs vs InertData KeptData s steps of
  ReducedUnder sw rs => case refContracts sw contracted of
    ContractedUnder sv cs => case constructorRead sv read of
      ReadAsRun run => RunAtConstructor run
      ReadAsConstructor at reads => HeadAtConstructor at (argumentsRead rs (argumentsIrreducible sw normal) cs reads)

||| The same at a type constructor of arguments: the type constructor over
||| what each argument reaches.
export
0 atFamily : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns []) ->
             Spine u (Ref fc (TyCon (S arity)) n) args ->
             Reduces ev ctx (putIn SizeOf.zero sz bs vs u) w -> Irreducible ev ctx w -> EtaContracts w v ->
             ReadAs (InstanceMode ctx) [] v r ->
             (a : Maybe Address ** ts : List Template **
               (r = Head a ts, AddressedAs (InstanceMode ctx) n a, ArgumentsRead ev ctx (map (putIn SizeOf.zero sz bs vs) args) ts))
atFamily sz bs vs s steps normal contracted read = case inertPutIn SizeOf.zero sz bs vs InertFamily KeptFamily s steps of
  ReducedUnder sw rs => case refContracts sw contracted of
    ContractedUnder sv cs => case familyRead sv read of
      (a ** ts ** (same, at, reads)) => (a ** ts ** (same, at, argumentsRead rs (argumentsIrreducible sw normal) cs reads))

||| The same at a bound name no value is put in for: the name over what
||| each argument reaches.
export
0 atBound : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns []) ->
            (0 _ : replaces bs n = False) -> Spine u (Ref fc Bound n) args ->
            Reduces ev ctx (putIn SizeOf.zero sz bs vs u) w -> Irreducible ev ctx w -> EtaContracts w v ->
            ReadAs (InstanceMode ctx) [] v r ->
            (ts : List Template ** (BoundRead n ts r, ArgumentsRead ev ctx (map (putIn SizeOf.zero sz bs vs) args) ts))
atBound sz bs vs none s steps normal contracted read = case inertPutIn SizeOf.zero sz bs vs InertBound (KeptBound none) s steps of
  ReducedUnder sw rs => case refContracts sw contracted of
    ContractedUnder sv cs => case boundRead sv read of
      (ts ** (named, reads)) => (ts ** (named, argumentsRead rs (argumentsIrreducible sw normal) cs reads))

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

||| One marker per field: where a match on the marker for x, which reads as
||| `Var i d`, meets the data constructor the instance's value for x is
||| applied (`Spine`), each field is put in for a marker of its own, read as
||| `Var i (S d)`: here y, for the field f. Where the markers held the
||| instance's values, they hold with that field's added. Any reading of the
||| field is a child of a reading of the constructor applied (`SData`, the
||| other fields read as any term is: `readsAnyAll`), which the markers hold
||| as another reading of a part of a value of V, so the field is another
||| reading of a part of that value one level deeper
||| (`Proof.Bound.fieldHolds`). The markers' names, fresh and apart, are the
||| walk's.
export
0 fieldMarkerHolds : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {ctx : Frozen} ->
                     {bs : Bounds ns} -> {vs : SubstEnv ns []} ->
                     MarkersHold m s ctx stands bs vs -> (x : Var ns) ->
                     walkMarker stands (replacedAt bs x) = Just (Template.Var i d) ->
                     Spine (Var.index vs x) (Ref fc (DataCon tag arity) cn) fields -> Elem f fields ->
                     walkMarker stands y = Just (Template.Var i (S d)) ->
                     MarkersHold m s ctx stands (Add new y bs) (f :: vs)
fieldMarkerHolds held x marked spine el named (MkVar First) i' d' named' u read =
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
fieldMarkerHolds held x marked spine el named (MkVar (Later w)) i' d' named' u read = held (MkVar w) i' d' named' u read

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
asGivenWrites (Just k) (Template.Chosen _) wr = Bound.Chosen Here wr
asGivenWrites (Just k) (Rooted _) wr = wr
asGivenWrites (Just k) (Gives _) wr = wr
asGivenWrites (Just k) (Parameter _ _) wr = wr
asGivenWrites (Just k) Unrooted wr = wr
asGivenWrites Nothing _ wr = wr

||| A landing where the value computes, which `landedAs` reads as computing.
public export
data LandsComputing : Landing -> Type where
  ComputedLands : LandsComputing Computed
  EvaluableLands : LandsComputing (Evaluable es)

||| What the graph's landings (`withClosedFamilies`) give the model at a
||| site: where only closed values no higher than k land at a family's
||| position, each position the site's writer reads the family at is one
||| that only such values reach (`Proof.Bound.Lands`), and the family's
||| value gives no member there; where its application computes, no
||| position of the writer's reads it and it gives no member; and the
||| implementations a dictionary of the site's can be are the same whether
||| its families are read landed or not.
public export
record LandingsWrite {g : Graph} (m : Model g) (s : Bound.Site g.size) (c : Nat -> Landing) where
  constructor MkLandingsWrite
  0 closedLands : (i, k : Nat) -> c i = Closed k -> (p : Fin g.size) -> Elem (i, p) s.writers -> Lands g m p k
  0 closedUnrooted : (i, k, d : Nat) -> (ts : List Template) -> c i = Closed k -> (j : Address) ->
                     Not (Elem j (s.roots (Applied i d ts)))
  0 computingUnread : (i, d : Nat) -> (ts : List Template) ->
                      Either (LandsComputing (c i)) (argumentsBeta c (allWithClosed c ts) = Template.Computes) ->
                      ((p : Fin g.size) -> Not (Elem (i, p) s.writers), (j : Address) -> Not (Elem j (s.roots (Applied i d ts))))
  0 rootsKept : (t : Template) -> (j : Address) -> Elem j (s.roots t) -> Elem j (s.roots (withClosedFamilies c t))

||| What writes a family of the writer's applied, its arguments' writes
||| already carried to the rewritten arguments.
public export
data AppliedWrites : {g : Graph} -> Model g -> Bound.Site g.size -> (i, d : Nat) -> (ts, ts' : List Template) -> Template -> Type where
  ByBeta : Elem (i, p) s.writers -> InV m p v -> Sub d v f -> Within f body -> AllWrite m s ts' ws ->
           Instantiates ws body w -> AppliedWrites m s i d ts ts' w
  ByPart : Elem (i, p) s.writers -> InV m p v -> Sub d v f -> Within f w -> AppliedWrites m s i d ts ts' w
  ByMember : Elem j (s.roots (Applied i d ts)) -> Arguments m j 0 as -> AppliedWrites m s i d ts ts' (Head (Just j) as)

-- Where no position of the writer's reads a family and its value gives no
-- member, nothing writes it applied.
0 unwritten : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} ->
              ((p : Fin g.size) -> Not (Elem (i, p) s.writers), (j : Address) -> Not (Elem j (s.roots (Applied i d ts)))) ->
              AppliedWrites m s i d ts ts' w -> Void
unwritten (nr, _) (ByBeta {p} wrote _ _ _ _ _) = nr p wrote
unwritten (nr, _) (ByPart {p} wrote _ _ _) = nr p wrote
unwritten (_, nm) (ByMember {j} rooted _) = nm j rooted

-- A family applied, rewritten: what wrote it writes it as the landing
-- reads it.
0 appliedLanded : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {c : Nat -> Landing} -> LandingsWrite m s c ->
                  (l : Landing) -> c i = l -> (b : Template.Beta) -> argumentsBeta c (allWithClosed c ts) = b ->
                  AppliedWrites m s i d ts (allWithClosed c ts) w -> Writes m s (landedAs l b i d (allWithClosed c ts)) w
appliedLanded ls Open isOpen Template.Inert inert (ByBeta wrote inV sub within aw inst) = Bound.Beta wrote inV sub within aw inst
appliedLanded ls Open isOpen Template.Inert inert (ByPart wrote inV sub within) = GivenPart wrote inV sub within
appliedLanded {i} {d} {ts} {c} ls Open isOpen Template.Inert inert (ByMember {j} rooted args) =
  MemberOf (replace {p = \b => Elem j (s.roots (landedAs Open b i d (allWithClosed c ts)))} inert
              (replace {p = \l => Elem j (s.roots (landedAs l (argumentsBeta c (allWithClosed c ts)) i d (allWithClosed c ts)))} isOpen
                 (ls.rootsKept (Applied i d ts) j rooted)))
           args
appliedLanded {i} ls (Closed k) isClosed Template.Inert inert (ByBeta {p} wrote inV sub within aw inst) =
  Landed (ls.closedLands i k isClosed p wrote) inV sub within aw inst
appliedLanded {i} ls (Closed k) isClosed Template.Inert inert (ByPart {p} wrote inV sub within) =
  LandedMember (ls.closedLands i k isClosed p wrote) inV sub within
appliedLanded {i} {d} {ts} ls (Closed k) isClosed Template.Inert inert (ByMember {j} rooted args) =
  void (ls.closedUnrooted i k d ts isClosed j rooted)
appliedLanded {i} {d} {ts} ls Computed isComputed b _ wr =
  void (unwritten (ls.computingUnread i d ts (Left (replace {p = LandsComputing} (sym isComputed) ComputedLands))) wr)
appliedLanded {i} {d} {ts} ls (Evaluable es) isEvaluable b _ wr =
  void (unwritten (ls.computingUnread i d ts (Left (replace {p = LandsComputing} (sym isEvaluable) EvaluableLands))) wr)
appliedLanded {i} {d} {ts} ls (Closed k) _ Template.Computes computes wr =
  void (unwritten (ls.computingUnread i d ts (Right computes)) wr)
appliedLanded {i} {d} {ts} ls Open _ Template.Computes computes wr =
  void (unwritten (ls.computingUnread i d ts (Right computes)) wr)

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
  ||| writes under the reading, it writes under the template the graph
  ||| keeps, where the landings are the model's (`LandingsWrite`).
  export
  0 closedWrites : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {c : Nat -> Landing} -> LandingsWrite m s c ->
                   Writes m s t w -> Writes m s (withClosedFamilies c t) w
  closedWrites ls (AtVar wrote inV sub again) = AtVar wrote inV sub again
  closedWrites ls (AtHead aw) = AtHead (allClosedWrites ls aw)
  closedWrites ls (AtOpaque aw) = AtOpaque (allClosedWrites ls aw)
  closedWrites ls AtLeaf = AtLeaf
  closedWrites ls (AtComputed aw form measured) = AtComputed (allClosedWrites ls aw) form measured
  closedWrites ls (AtRun wr run) = AtRun (closedWrites ls wr) run
  closedWrites ls (AtCut wr high) = AtCut (closedWrites ls wr) high
  closedWrites ls AtToken = AtToken
  closedWrites ls AtFormal = AtFormal
  closedWrites {c} ls (Bound.Chosen el wr) = Bound.Chosen (closedElem {c} el) (closedWrites ls wr)
  closedWrites {c} ls (AtContracted el wr drops) = AtContracted (closedElem {c} el) (closedWrites ls wr) drops
  closedWrites {c} ls (Bound.Beta {i} {d} {ts} wrote inV sub within aw inst) =
    appliedLanded {i} {d} {ts} ls (c i) Refl (argumentsBeta c (allWithClosed c ts)) Refl
                  (ByBeta wrote inV sub within (allClosedWrites ls aw) inst)
  closedWrites {c} ls (GivenPart {i} {d} {ts} wrote inV sub within) =
    appliedLanded {i} {d} {ts} ls (c i) Refl (argumentsBeta c (allWithClosed c ts)) Refl (ByPart wrote inV sub within)
  closedWrites {c} ls (MemberOf {i} {d} {ts} rooted args) =
    appliedLanded {i} {d} {ts} ls (c i) Refl (argumentsBeta c (allWithClosed c ts)) Refl (ByMember rooted args)
  closedWrites {c} ls (Landed {k} {ts} lands inV sub within aw inst) =
    rewrite closedRaise {c} k (Head Nothing ts) in Landed lands inV sub within (allClosedWrites ls aw) inst
  closedWrites {c} ls (LandedMember {k} {ts} lands inV sub within) =
    rewrite closedRaise {c} k (Head Nothing ts) in LandedMember lands inV sub within
  closedWrites ls (AtField {r} {j} rooted at inV) = AtField (ls.rootsKept r j rooted) at inV
  closedWrites ls (AtMember at inV renumbered) = AtMember at inV renumbered
  closedWrites ls (AtHeldHole at inV high within) = AtHeldHole at inV high within

  0 allClosedWrites : {g : Graph} -> {m : Model g} -> {s : Bound.Site g.size} -> {c : Nat -> Landing} -> LandingsWrite m s c ->
                      AllWrite m s ts ws -> AllWrite m s (allWithClosed c ts) ws
  allClosedWrites ls [] = []
  allClosedWrites ls (wr :: aw) = closedWrites ls wr :: allClosedWrites ls aw

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
runOnce Keys.RunZero Keys.RunZero = Refl
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
  runSpineRead Keys.RunZero (SData _ []) = RunReadZero
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
||| requesting instance's site gives (`Template.siteWritesFrom`).
public export
data ArgumentFrom : {g : Graph} -> Model g -> Bound.Site g.size -> Frozen -> (i, d : Nat) -> ClosedTerm -> Type where
  WrittenArgument : {0 k : State.Static} -> {0 t : ClosedTerm} -> (p : Fin g.size) -> Elem (i, p) s.writers ->
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
