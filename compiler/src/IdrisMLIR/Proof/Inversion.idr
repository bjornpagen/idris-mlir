-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The host's reduction (`Idris.Host.Reduces`) and the frontend's eta
||| contraction (`Proof.Reading.EtaContracts`) inverted where a reading of
||| an instance's term meets a node whose head no step rewrites.
|||
||| A site's reading and an instance's reading of one static argument are
||| related node by node, the instance's term being the site's with a value
||| put in for each marker, normalised and contracted. At a node headed by
||| a bound name (a marker, a hole, a runtime part), a data constructor, or
||| a type constructor that takes arguments, no step of the evaluator
||| applies at the root (`noRootStep`), so every reduction of it, however
||| its steps are chained, keeps the head and reduces each argument
||| (`inertReduces`); an argument of a normal form is normal
||| (`argumentIrreducible`); and contraction, which rewrites only a
||| lambda, keeps the head and contracts each argument (`refContracts`).
||| So the instance's form at such a node is the same head over the forms
||| of its arguments, which the reading lemma's induction descends into.
||| Alone, or applied to one argument, such a head reduces to itself over
||| what the argument reduces to (`inertAlone`, `inertOne`); and two heads
||| no step rewrites either, an erased part no dot holds and a name the
||| context defines as nothing, reduce only to themselves
||| (`erasedReduces`, `undefinedReduces`).
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Inversion

import Core.Context
import Core.TT
import Idris.Host

import IdrisMLIR.Proof.Reading

import Data.List
import Data.List.Elem

%default total

------------------------------------------------------------------------------
-- Spines headed by a reference
------------------------------------------------------------------------------

||| A term headed by a reference has one such head and one list of
||| arguments: a spine reaches its head through applications alone.
export
0 refSpines : Spine t (Ref fc nt n) args -> Spine t (Ref fc' nt' n') args' ->
              (Ref fc nt n = Ref fc' nt' n', args = args')
refSpines Head Head = (Refl, Refl)
refSpines Head (Applied _) impossible
refSpines (Applied _) Head impossible
refSpines (Applied s) (Applied s') = case refSpines s s' of
  (Refl, Refl) => (Refl, Refl)

-- A spine headed by a reference never passes through any node but an
-- application: each of these is a head of its own.

0 notBind : Spine (Bind fc x b sc) (Ref rfc nt n) args -> Void
notBind Head impossible
notBind (Applied _) impossible

0 notAs : Spine (As fc side a p) (Ref rfc nt n) args -> Void
notAs Head impossible
notAs (Applied _) impossible

0 notDelayed : Spine (TDelayed fc r t) (Ref rfc nt n) args -> Void
notDelayed Head impossible
notDelayed (Applied _) impossible

0 notDelay : Spine (TDelay fc r ty a) (Ref rfc nt n) args -> Void
notDelay Head impossible
notDelay (Applied _) impossible

0 notForce : Spine (TForce fc r t) (Ref rfc nt n) args -> Void
notForce Head impossible
notForce (Applied _) impossible

export
0 notErased : Spine (Erased fc why) (Ref rfc nt n) args -> Void
notErased Head impossible
notErased (Applied _) impossible

0 notConstant : Spine (PrimVal fc c) (Ref rfc nt n) args -> Void
notConstant Head impossible
notConstant (Applied _) impossible

0 notUniverse : Spine (TType fc u) (Ref rfc nt n) args -> Void
notUniverse Head impossible
notUniverse (Applied _) impossible

0 notLocal : Spine (Local fc l idx p) (Ref rfc nt n) args -> Void
notLocal Head impossible
notLocal (Applied _) impossible

0 notMeta : Spine (Meta fc m i scope) (Ref rfc nt n) args -> Void
notMeta Head impossible
notMeta (Applied _) impossible

||| A term headed by a reference is headed by no unknown.
export
0 refNotMeta : Spine t (Ref fc nt n) args -> Spine t (Meta mfc m i scope) more -> Void
refNotMeta Head Head impossible
refNotMeta Head (Applied _) impossible
refNotMeta (Applied _) Head impossible
refNotMeta (Applied s) (Applied s') = refNotMeta s s'

-- A head that drops what it is applied to is no reference.
0 droppedHead : DropsArguments f -> Spine f (Ref rfc nt n) args -> Void
droppedHead DropsAtPlaceholder s = notErased s
droppedHead DropsAtImpossible s = notErased s
droppedHead DropsAtConstant s = notConstant s
droppedHead DropsAtUniverse s = notUniverse s
droppedHead DropsAtDelay s = notDelay s

------------------------------------------------------------------------------
-- Inert heads
------------------------------------------------------------------------------

||| A head no step of the evaluator rewrites, whatever it is applied to: a
||| bound name, which no step reads (a step reads a function, a
||| constructor or a family through its kind and its entry); a data
||| constructor; or a type constructor that takes arguments. A type
||| constructor of none is the universe or a primitive type by its name,
||| which a step rewrites, and a function is what steps unfold: neither is
||| one.
public export
data Inert : NameType -> Type where
  InertBound : Inert Bound
  InertData : Inert (DataCon tag arity)
  InertFamily : Inert (TyCon (S arity))

export
Uninhabited (Inert Func) where
  uninhabited InertBound impossible
  uninhabited InertData impossible
  uninhabited InertFamily impossible

export
Uninhabited (Inert (TyCon Z)) where
  uninhabited InertBound impossible
  uninhabited InertData impossible
  uninhabited InertFamily impossible

-- A function's spine is no inert head's.
0 funcHead : Inert nt -> Spine t (Ref fc nt n) args -> Spine t (Ref fc' Func n') args' -> Void
funcHead inert s s' = case refSpines s s' of
  (Refl, _) => absurd inert

||| No step of the evaluator applies at the root of a term an inert head
||| heads: each step's left side is a lambda or a `let` applied or alone,
||| an as pattern, a force, a binder, a lazy type, a dot or a head that
||| drops its arguments applied, a function or an unknown applied, or a
||| type constructor of no arguments alone.
export
0 noRootStep : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
               Inert nt -> Spine t (Ref fc nt n) args -> Contracts ev ctx t u -> Void
noRootStep inert Head Beta impossible
noRootStep inert (Applied s) Beta = notBind s
noRootStep inert s (Zeta _) = notBind s
noRootStep inert s (Unfold s' _ _ _ _ _ _ _) = funcHead inert s s'
noRootStep inert s (Solve s' _ _ _ _ _ _ _ _) = refNotMeta s s'
noRootStep inert s (Primitive s' _ _ _ _ _) = funcHead inert s s'
noRootStep inert s ForceDelay = notForce s
noRootStep inert s (RemoveAs _) = notAs s
noRootStep inert Head (FloatAs _) impossible
noRootStep inert (Applied s) (FloatAs _) = notAs s
noRootStep inert Head (FloatBinder _) impossible
noRootStep inert (Applied s) (FloatBinder _) = notBind s
noRootStep inert Head FloatDelayed impossible
noRootStep inert (Applied s) FloatDelayed = notDelayed s
noRootStep inert Head FloatDot impossible
noRootStep inert (Applied s) FloatDot = notErased s
noRootStep inert Head (DropApplied _) impossible
noRootStep inert (Applied s) (DropApplied dropped) = droppedHead dropped s
noRootStep inert Head (TypeName _) = absurd inert
noRootStep inert (Applied _) (TypeName _) impossible
noRootStep inert Head (ConstantTypeName _) = absurd inert
noRootStep inert (Applied _) (ConstantTypeName _) impossible

------------------------------------------------------------------------------
-- Reduction under an inert head
------------------------------------------------------------------------------

||| Two lists of terms, each reducing to the other's term in turn, chained.
export
0 allThen : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
            AllReduce ev ctx as bs -> AllReduce ev ctx bs cs -> AllReduce ev ctx as cs
allThen NoneLeft NoneLeft = NoneLeft
allThen NoneLeft (Each _ _) impossible
allThen (Each _ _) NoneLeft impossible
allThen (Each r rs) (Each r' rs') = Each (Then r r') (allThen rs rs')

||| One more argument, reduced, after arguments reduced.
export
0 allSnoc : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
            AllReduce ev ctx as bs -> Reduces ev ctx a b -> AllReduce ev ctx (as ++ [a]) (bs ++ [b])
allSnoc NoneLeft r = Each r NoneLeft
allSnoc (Each r' rs) r = Each r' (allSnoc rs r)

||| What a reduction makes of a term an inert head heads: the same head,
||| at some location, applied to what each argument reduces to.
public export
data InertReduct : {0 vs : Scope} -> Evaluation -> Frozen -> NameType -> Name -> List (Term vs) -> Term vs -> Type where
  ReducedUnder : {0 ev : Evaluation} -> {0 ctx : Frozen} -> {0 args, args' : List (Term vs)} ->
                 Spine u (Ref fc' nt n) args' -> AllReduce ev ctx args args' -> InertReduct ev ctx nt n args u

||| A term an inert head heads reduces only under its arguments: no step
||| applies at its root (`noRootStep`), an application's congruence keeps
||| the head of its function and reduces its argument, a reference's keeps
||| the reference, and a chain of reductions chains what each makes of the
||| arguments.
export
0 inertReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Inert nt ->
                 Spine t (Ref fc nt n) args -> Reduces ev ctx t u -> InertReduct ev ctx nt n args u
inertReduces inert s (Then r r') = case inertReduces inert s r of
  ReducedUnder s' rs => case inertReduces inert s' r' of
    ReducedUnder s'' rs' => ReducedUnder s'' (allThen rs rs')
inertReduces inert s (Contract c) = void (noRootStep inert s c)
inertReduces inert Head ARef = ReducedUnder Head NoneLeft
inertReduces inert (Applied s) ARef impossible
inertReduces inert (Applied s) (AnApp rf ra) = case inertReduces inert s rf of
  ReducedUnder s' rs => ReducedUnder (Applied s') (allSnoc rs ra)
inertReduces inert Head (AnApp _ _) impossible
inertReduces inert s ALocal = void (notLocal s)
inertReduces inert s (AMeta _) = void (notMeta s)
inertReduces inert s (ABind _ _) = void (notBind s)
inertReduces inert s (AnAs _ _) = void (notAs s)
inertReduces inert s (ADelayed _) = void (notDelayed s)
inertReduces inert s (ADelay _ _) = void (notDelay s)
inertReduces inert s (AForce _) = void (notForce s)
inertReduces inert s APrimVal = void (notConstant s)
inertReduces inert s (AnErased _) = void (notErased s)
inertReduces inert s AType = void (notUniverse s)

------------------------------------------------------------------------------
-- Spines of no argument and of one
------------------------------------------------------------------------------

-- A list one element longer at its end is never empty.
0 snocNotNil : (xs : List a) -> xs ++ [x] = [] -> Void
snocNotNil [] Refl impossible
snocNotNil (_ :: _) Refl impossible

0 nilNotCons : the (List a) [] = x :: xs -> Void
nilNotCons Refl impossible

-- A list one element longer at its end is one element only where it was
-- empty, and that element is the one added.
0 snocOne : (xs : List a) -> xs ++ [x] = [y] -> (xs = [], x = y)
snocOne [] Refl = (Refl, Refl)
snocOne (_ :: zs) eq = void (snocNotNil zs (snd (consInjective eq)))

||| A spine of no argument is its head.
export
0 headOnly : Spine t h args -> args = [] -> t = h
headOnly Head _ = Refl
headOnly (Applied {args = xs} _) eq = void (snocNotNil xs eq)

||| A spine of one argument is its head applied to it.
export
0 oneApplied : Spine t h args -> args = [x] -> (fc : FC ** t = App fc h x)
oneApplied Head eq = void (nilNotCons eq)
oneApplied (Applied {fc} {a} {args = xs} s) eq = case snocOne xs eq of
  (Refl, Refl) => (fc ** cong (\g => App fc g a) (headOnly s Refl))

||| What an inert head alone reduces to: itself, at some location.
export
0 inertAlone : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Inert nt ->
               Reduces ev ctx (Ref fc nt n) v -> (fc' : FC ** v = Ref fc' nt n)
inertAlone inert r = case inertReduces inert Head r of
  ReducedUnder s NoneLeft => (_ ** headOnly s Refl)

||| What an inert head applied to one argument reduces to: the head, at
||| some location, applied to what the argument reduces to.
export
0 inertOne : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Inert nt ->
             Reduces ev ctx (App fc (Ref rfc nt n) a) v ->
             (fc' : FC ** rfc' : FC ** a' : Term vs ** (v = App fc' (Ref rfc' nt n) a', Reduces ev ctx a a'))
inertOne inert r = case inertReduces inert (Applied Head) r of
  ReducedUnder s (Each ra NoneLeft) => case oneApplied s Refl of
    (fc' ** same) => (fc' ** _ ** _ ** (same, ra))

------------------------------------------------------------------------------
-- Heads that reduce only to themselves
------------------------------------------------------------------------------

||| An erased part no dot holds: a placeholder, or what is impossible.
public export
data Undotted : WhyErased (Term vs) -> Type where
  IsPlaceholder : Undotted Placeholder
  IsImpossible : Undotted Impossible

-- A term an erased part heads is headed by no unknown.
0 erasedNotMeta : Spine (Erased fc why) (Meta mfc m i scope) more -> Void
erasedNotMeta Head impossible
erasedNotMeta (Applied _) impossible

-- No step of the evaluator applies at the root of an erased part: each
-- step's left side is a node of another form, or a function, an unknown
-- or a type constructor at the head of its spine.
0 erasedNoStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Contracts ev ctx (Erased fc why) u -> Void
erasedNoStep (Unfold s _ _ _ _ _ _ _) = notErased s
erasedNoStep (Solve s _ _ _ _ _ _ _ _) = erasedNotMeta s
erasedNoStep (Primitive s _ _ _ _ _) = notErased s

||| What an erased part no dot holds reduces to: itself, at some location.
export
0 erasedReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Undotted why ->
                  Reduces ev ctx (Erased fc why) v -> (fc' : FC ** v = Erased fc' why)
erasedReduces u (Then r r') = case erasedReduces u r of
  (_ ** Refl) => erasedReduces u r'
erasedReduces u (Contract c) = void (erasedNoStep c)
erasedReduces IsPlaceholder (AnErased APlaceholder) = (_ ** Refl)
erasedReduces IsImpossible (AnErased AnImpossible) = (_ ** Refl)

-- No step of the evaluator applies at a name the context defines as
-- nothing: a step that unfolds a name or computes a primitive unfolds the
-- definition the context gives it, and a function is no unknown.
0 undefinedNoStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> ((d : GlobalDef) -> Not (Defines ctx n d)) ->
                    Contracts ev ctx (Ref fc Func n) u -> Void
undefinedNoStep none (Unfold s defines _ _ _ _ _ _) = case refSpines Head s of
  (Refl, _) => none _ defines
undefinedNoStep none (Solve s _ _ _ _ _ _ _ _) = refNotMeta Head s
undefinedNoStep none (Primitive s defines _ _ _ _) = case refSpines Head s of
  (Refl, _) => none _ defines

||| What a name the context defines as nothing reduces to: itself, at
||| some location.
export
0 undefinedReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> ((d : GlobalDef) -> Not (Defines ctx n d)) ->
                     Reduces ev ctx (Ref fc Func n) v -> (fc' : FC ** v = Ref fc' Func n)
undefinedReduces none (Then r r') = case undefinedReduces none r of
  (_ ** Refl) => undefinedReduces none r'
undefinedReduces none (Contract c) = void (undefinedNoStep none c)
undefinedReduces none ARef = (_ ** Refl)

------------------------------------------------------------------------------
-- A normal form's arguments
------------------------------------------------------------------------------

0 splitElem : (xs : List a) -> Elem x (xs ++ ys) -> Either (Elem x xs) (Elem x ys)
splitElem [] e = Right e
splitElem (_ :: xs) Here = Left Here
splitElem (_ :: xs) (There e) = case splitElem xs e of
  Left l => Left (There l)
  Right r => Right r

-- A step in an argument of a spine is a step of the term, under the
-- applications that apply the head to the arguments.
0 liftedRedex : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
                Spine u h args -> Elem a args -> Redex ev ctx a -> Redex ev ctx u
liftedRedex Head el r = absurd el
liftedRedex (Applied {args = xs} s) el r = case splitElem xs el of
  Left inFunction => InFunction (liftedRedex s inFunction r)
  Right Here => InArgument r
  Right (There e) => absurd e

||| An argument of a normal form is normal.
export
0 argumentIrreducible : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
                        Spine u h args -> Elem a args -> Irreducible ev ctx u -> Irreducible ev ctx a
argumentIrreducible s el normal redex = normal (liftedRedex s el redex)

------------------------------------------------------------------------------
-- Contraction under a reference
------------------------------------------------------------------------------

||| Terms each contracted to the other's term in turn.
public export
data AllContract : List (Term vs) -> List (Term vs) -> Type where
  NoneContracted : AllContract [] []
  EachContracted : EtaContracts t u -> AllContract ts us -> AllContract (t :: ts) (u :: us)

-- Every list of terms is itself contracted.
0 noneChanged : (ts : List (Term vs)) -> AllContract ts ts
noneChanged [] = NoneContracted
noneChanged (t :: ts) = EachContracted EtaSame (noneChanged ts)

-- One more argument, contracted, after arguments contracted.
0 contractedSnoc : AllContract xs ys -> EtaContracts a b -> AllContract (xs ++ [a]) (ys ++ [b])
contractedSnoc NoneContracted c = EachContracted c NoneContracted
contractedSnoc (EachContracted c' cs) c = EachContracted c' (contractedSnoc cs c)

||| What contraction makes of a term a reference heads: the same head, at
||| the same location, applied to each argument contracted.
public export
data RefContracted : {0 vs : Scope} -> FC -> NameType -> Name -> List (Term vs) -> Term vs -> Type where
  ContractedUnder : {0 args, args' : List (Term vs)} ->
                    Spine u (Ref fc nt n) args' -> AllContract args args' -> RefContracted fc nt n args u

||| Contraction keeps the head of a term a reference heads and contracts
||| each argument: a redex is a lambda, which no such term is, and every
||| other node it rewrites is a head of its own.
export
0 refContracts : Spine v (Ref fc nt n) args -> EtaContracts v u -> RefContracted fc nt n args u
refContracts {args} s EtaSame = ContractedUnder s (noneChanged args)
refContracts (Applied s) (EtaApp cf ca) = case refContracts s cf of
  ContractedUnder s' cs => ContractedUnder (Applied s') (contractedSnoc cs ca)
refContracts Head (EtaApp _ _) impossible
refContracts s (EtaRedex _ _) = void (notBind s)
refContracts s (EtaBind _ _) = void (notBind s)
refContracts s (EtaAs _ _) = void (notAs s)
refContracts s (EtaDelayed _) = void (notDelayed s)
refContracts s (EtaDelay _ _) = void (notDelay s)
refContracts s (EtaForce _) = void (notForce s)
refContracts s (EtaDotted _) = void (notErased s)
